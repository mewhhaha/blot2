import Base

def max_nat48() -> Nat:
  Nat.add(Nat.mul(U32.to_nat(4294967295), 65536n), 65535n)

def heap_key(last: U32) -> String:
  SCon{Chr{65}, SCon{Chr{0}, SCon{Chr{128578}, SCon{Chr{last}, SNil{}}}}}

def result_bit(result: String & Bool) -> Bool:
  (key, bit) = result
  bit

def after_cmp(result: (String & String) & Cmp) -> Bool:
  ((value, right), order) = result
  +left = value
  Bool.and(String.eq(left, heap_key(65)), result_bit(Map.bit(left, Nat.add(max_nat48(), 1n))))

def main() -> Bool:
  after_cmp(String.cmp(heap_key(65), heap_key(66)))
