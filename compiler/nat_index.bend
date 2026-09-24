import Base

# A persistent Patricia index for Bend's 48-bit Nat keys. A branch's sample is any key in
# its subtree; every key under it shares the bits above mask. The two children
# differ at mask, so lookup visits only occupied branching positions.
type Index<-V: Data> is Data:
  Empty{}
  Leaf{key: Nat, value: V}
  Branch{sample: Nat, mask: Nat, low: Index<V>, high: Index<V>}

def new(-V: Data) -> Index<V>:
  Empty{}

# For distinct keys, halve both until their next halves agree. The current
# mask is then their highest differing bit; this never forms 2^48.
type Difference is Data:
  Halve{left: Nat, right: Nat, mask: Nat}
  Decide{left: Nat, right: Nat, mask: Nat, same: Bool}

def difference(fuel: Nat, work: Difference) -> Nat:
  # Distinct Nat48 keys need at most two states per bit, so link's 96 fuel
  # always reaches Decide(True) before this fallback.
  match fuel work:
    case 0n _:
      0n
    case 1n+rest Halve{left, right, mask}:
      +a = Nat.div(left, 2n)
      +b = Nat.div(right, 2n)
      difference(rest, Decide{a, b, mask, Nat.is_eq(a, b)})
    case 1n+rest Decide{left, right, mask, True{}}:
      mask
    case 1n+rest Decide{left, right, mask, False{}}:
      difference(rest, Halve{left, right, Nat.mul(mask, 2n)})

def prefix(key: Nat, mask: Nat) -> Nat:
  Nat.div(Nat.div(key, mask), 2n)

def same_prefix(key: Nat, sample: Nat, +mask: Nat) -> Bool:
  Nat.is_eq(prefix(key, mask), prefix(sample, mask))

def high_bit(key: Nat, mask: Nat) -> Bool:
  Nat.is_ne(Nat.mod(Nat.div(key, mask), 2n), 0n)

def linked(-V: Data, high: Bool, sample: Nat, mask: Nat, a: Index<V>, b: Index<V>) -> Index<V>:
  match high:
    case False{}:
      Branch{sample, mask, a, b}
    case True{}:
      Branch{sample, mask, b, a}

def link(-V: Data, +key: Nat, value: Index<V>, other_key: Nat, other: Index<V>) -> Index<V>:
  +mask = difference(96n, Halve{key, other_key, 1n})
  linked(V, high_bit(key, mask), key, mask, value, other)

type Insert<-V: Data> is Data:
  Enter{index: Index<V>, key: Nat, value: V}
  CompareLeaf{old_key: Nat, old_value: V, key: Nat, value: V, same: Bool}
  CompareBranch{sample: Nat, mask: Nat, low: Index<V>, high: Index<V>, key: Nat, value: V, within: Bool}
  ChooseBranch{sample: Nat, mask: Nat, low: Index<V>, high: Index<V>, key: Nat, value: V, upper: Bool}

def insert(-V: Data, fuel: Nat, work: Insert<V>) -> Index<V>:
  # Each branch consumes at most three states. A Patricia path has at most
  # 48 branches, then at most two leaf states: 146 < set's 160 fuel.
  match fuel work:
    case 0n _:
      Empty{}
    case 1n+rest Enter{Empty{}, key, value}:
      Leaf{key, value}
    case 1n+rest Enter{Leaf{+old_key, old_value}, +key, value}:
      insert(V, rest, CompareLeaf{old_key, old_value, key, value, Nat.is_eq(old_key, key)})
    case 1n+rest CompareLeaf{old_key, old_value, key, value, True{}}:
      Leaf{key, value}
    case 1n+rest CompareLeaf{+old_key, old_value, +key, value, False{}}:
      link(V, key, Leaf{key, value}, old_key, Leaf{old_key, old_value})
    case 1n+rest Enter{Branch{+sample, +mask, low, high}, +key, value}:
      insert(V, rest, CompareBranch{sample, mask, low, high, key, value, same_prefix(key, sample, mask)})
    case 1n+rest CompareBranch{+sample, mask, low, high, +key, value, False{}}:
      link(V, key, Leaf{key, value}, sample, Branch{sample, mask, low, high})
    case 1n+rest CompareBranch{sample, +mask, low, high, +key, value, True{}}:
      insert(V, rest, ChooseBranch{sample, mask, low, high, key, value, high_bit(key, mask)})
    case 1n+rest ChooseBranch{sample, mask, low, high, key, value, False{}}:
      Branch{sample, mask, insert(V, rest, Enter{low, key, value}), high}
    case 1n+rest ChooseBranch{sample, mask, low, high, key, value, True{}}:
      Branch{sample, mask, low, insert(V, rest, Enter{high, key, value})}

def set(-V: Data, index: Index<V>, key: Nat, value: V) -> Index<V>:
  insert(V, 160n, Enter{index, key, value})

def choose(-V: Data, upper: Bool, right: Unit -> Maybe<&2, V>, left: Unit -> Maybe<&2, V>) -> Maybe<&2, V>:
  match upper:
    case True{}:
      right(Unit{})
    case False{}:
      left(Unit{})

def within(-V: Data, same: Bool, found: Unit -> Maybe<&2, V>) -> Maybe<&2, V>:
  match same:
    case True{}:
      found(Unit{})
    case False{}:
      None{}

def find(-V: Data, index: Index<V>, +key: Nat) -> Maybe<&2, V>:
  match index:
    case Empty{}:
      None{}
    case Leaf{found, value}:
      Bool.pick(Maybe<&2, V>, Nat.is_eq(found, key), Some{value}, None{})
    case Branch{sample, +mask, low, high}:
      within(V, same_prefix(key, sample, mask), unit => choose(V, high_bit(key, mask), unit => find(V, high, key), unit => find(V, low, key)))

def fallback(-V: Data, found: Maybe<&2, V>, otherwise: V) -> V:
  match found:
    case None{}:
      otherwise
    case Some{value}:
      value

def get(-V: Data, index: Index<V>, key: Nat, otherwise: V) -> V:
  fallback(V, find(V, index, key), otherwise)
