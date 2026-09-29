import Base
import ./nat_index.bend as N

def missing(found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}:
      True{}
    case Some{value}:
      False{}

def boundary_valid() -> Bool:
  +highest = Nat.mul(16777216n, 8388608n)
  +last = Nat.add(highest, Nat.sub(highest, 1n))
  +base = {N.set(U32, N.new(U32), 0n, 10) : N.Index<U32>}
  +low = {N.set(U32, base, 1n, 11) : N.Index<U32>}
  +high = {N.set(U32, low, highest, 12) : N.Index<U32>}
  +wide = {N.set(U32, high, last, 13) : N.Index<U32>}
  +updated = {N.set(U32, wide, 1n, 21) : N.Index<U32>}
  Bool.and(U32.is_eq(N.get(U32, base, 0n, 0), 10),
    Bool.and(missing(N.find(U32, base, 1n)),
    Bool.and(U32.is_eq(N.get(U32, low, 1n, 0), 11),
    Bool.and(U32.is_eq(N.get(U32, high, highest, 0), 12),
    Bool.and(U32.is_eq(N.get(U32, wide, last, 0), 13),
    Bool.and(U32.is_eq(N.get(U32, wide, 1n, 0), 11),
    Bool.and(U32.is_eq(N.get(U32, updated, 1n, 0), 21),
      missing(N.find(U32, updated, Nat.add(highest, 1n))))))))))

# Zero lies below every branching bit when each one-bit key is also present.
def path_index(remaining: Nat, +bit: Nat, index: N.Index<U32>) -> N.Index<U32>:
  match remaining:
    case 0n:
      index
    case 1n+rest:
      path_index(rest, Nat.div(bit, 2n), N.set(U32, index, bit, 42))

def path_keys_valid(remaining: Nat, +bit: Nat, +index: N.Index<U32>) -> Bool:
  match remaining:
    case 0n:
      U32.is_eq(N.get(U32, index, 0n, 0), 99)
    case 1n+rest:
      Bool.and(U32.is_eq(N.get(U32, index, bit, 0), 42), path_keys_valid(rest, Nat.div(bit, 2n), index))

def valid() -> Bool:
  +highest = Nat.mul(16777216n, 8388608n)
  +index = path_index(48n, highest, N.set(U32, N.new(U32), 0n, 99))
  Bool.and(boundary_valid(), Bool.and(path_keys_valid(48n, highest, index), missing(N.find(U32, index, 3n))))

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "numeric Patricia index regression failed")

def main() -> IO(Unit):
  finish(valid())
