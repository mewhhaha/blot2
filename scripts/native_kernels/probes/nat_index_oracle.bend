import Base
import ../../../compiler/nat_index.bend as N

type Payload is Data:
  Payload{tag: String, values: List<&2, U32>}

def item(tag: String, value: U32) -> Payload:
  Payload{tag, [value, 2, 3]}

def same(found: Maybe<&2, Payload>, wanted: String, value: U32) -> Bool:
  match found:
    case Some{Payload{tag, a <> b <> c <> Nil{}}}:
      Bool.and(String.eq(tag, wanted), Bool.and(U32.is_eq(a, value), Bool.and(U32.is_eq(b, 2), U32.is_eq(c, 3))))
    case _:
      False{}

def missing(found: Maybe<&2, Payload>) -> Bool:
  match found:
    case None{}:
      True{}
    case _:
      False{}

def high_bit() -> Nat:
  Nat.mul(16777216n, 8388608n)

def last_key() -> Nat:
  Nat.add(high_bit(), Nat.sub(high_bit(), 1n))

def fill(+count: Nat, index: N.Index<Payload>) -> N.Index<Payload>:
  match count:
    case 0n:
      index
    case 1n+rest:
      fill(rest, N.set(Payload, index, Nat.mul(count, 97n), item(Nat.show(count), U32.from_nat(count))))

def repeated(+index: N.Index<Payload>, count: Nat) -> Bool:
  match count:
    case 0n:
      True{}
    case 1n+rest:
      Bool.and(same(N.find(Payload, index, last_key()), "last", 13),
        Bool.and(missing(N.find(Payload, index, Nat.add(high_bit(), 1n))), repeated(index, rest)))

def check() -> Bool:
  +empty = {N.new(Payload) : N.Index<Payload>}
  +zero = N.set(Payload, empty, 0n, item("zero", 10))
  +one = N.set(Payload, zero, 1n, item("one", 11))
  +middle = N.set(Payload, one, Nat.sub(high_bit(), 1n), item("middle", 12))
  +high = N.set(Payload, middle, high_bit(), item("high", 14))
  +wide = N.set(Payload, high, last_key(), item("last", 13))
  +updated = N.set(Payload, wide, 1n, item("changed", 21))
  +many = fill(96n, wide)
  +zero_mask = {N.Branch{0n, 0n, N.Leaf{0n, item("zero", 10)}, N.Leaf{1n, item("one", 11)}} : N.Index<Payload>}
  +odd_mask = {N.Branch{0n, 3n, N.Leaf{0n, item("zero", 10)}, N.Leaf{3n, item("three", 3)}} : N.Index<Payload>}
  a b = repeated(wide, 512n) repeated(many, 512n)
  Bool.and(missing(N.find(Payload, empty, 0n)),
    Bool.and(same(N.find(Payload, zero, 0n), "zero", 10),
    Bool.and(missing(N.find(Payload, zero, 1n)),
    Bool.and(same(N.find(Payload, one, 1n), "one", 11),
    Bool.and(missing(N.find(Payload, one, last_key())),
    Bool.and(same(N.find(Payload, middle, Nat.sub(high_bit(), 1n)), "middle", 12),
    Bool.and(missing(N.find(Payload, middle, high_bit())),
    Bool.and(same(N.find(Payload, high, high_bit()), "high", 14),
    Bool.and(same(N.find(Payload, wide, last_key()), "last", 13),
    Bool.and(missing(N.find(Payload, wide, Nat.sub(last_key(), 1n))),
    Bool.and(same(N.find(Payload, updated, 1n), "changed", 21),
    Bool.and(same(N.find(Payload, wide, 1n), "one", 11),
    Bool.and(same(N.find(Payload, many, 97n), "1", 1),
    Bool.and(same(N.find(Payload, many, Nat.mul(96n, 97n)), "96", 96),
    Bool.and(same(N.find(Payload, zero_mask, 0n), "zero", 10),
    Bool.and(missing(N.find(Payload, zero_mask, 1n)),
    Bool.and(same(N.find(Payload, odd_mask, 3n), "three", 3),
    Bool.and(a, b))))))))))))))))))

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("NAT_INDEX_OK")
    case False{}:
      IO.die(Unit, 1, "NatIndex native ownership or boundary mismatch")

def main() -> IO(Unit):
  finish(check())
