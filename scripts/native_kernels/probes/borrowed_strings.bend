import Base

def sign(value: Cmp) -> U32:
  match value:
    case LT{}: 0
    case EQ{}: 1
    case GT{}: 2

def checked_cmp(left: String, right: String, result: (String & String) & Cmp) -> U32:
  ((a, b), order) = result
  Bool.pick(U32, Bool.and(String.eq(a, left), String.eq(b, right)), sign(order), 99)

def compare(+left: String, +right: String) -> U32:
  checked_cmp(left, right, String.cmp(left, right))

def heap_key(last: U32) -> String:
  SCon{Chr{65}, SCon{Chr{0}, SCon{Chr{128578}, SCon{Chr{last}, SNil{}}}}}

def checked_bit(expected: String, result: String & Bool) -> U32:
  (key, bit) = result
  Bool.pick(U32, String.eq(key, expected), Bool.to_u32(bit), 99)

def max_nat48() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(4294967295), 65536n), 65535n)

def shared() -> List<&2, U32>:
  +key = heap_key(65)
  first second third = compare(key, key) checked_bit(heap_key(65), Map.bit(key, 0n)) checked_bit(heap_key(65), Map.bit(key, 33n))
  [first, second, third]

def main() -> List<&2, U32>:
  List.append(&2, U32,
    [compare("", ""), compare("", "a"), compare("a", ""), compare("ab", "abc"), compare("abc", "ab"), compare(heap_key(0), heap_key(4294967295)), compare(heap_key(4294967295), heap_key(0)), compare(heap_key(65), heap_key(65)), checked_bit(heap_key(65), Map.bit(heap_key(65), 0n)), checked_bit(heap_key(65), Map.bit(heap_key(65), 26n)), checked_bit(heap_key(65), Map.bit(heap_key(65), 32n)), checked_bit(heap_key(65), Map.bit(heap_key(65), 34n)), checked_bit(heap_key(4294967295), Map.bit(heap_key(4294967295), 100n)), checked_bit(heap_key(4294967295), Map.bit(heap_key(4294967295), 131n)), checked_bit(heap_key(65), Map.bit(heap_key(65), max_nat48()))], shared())
