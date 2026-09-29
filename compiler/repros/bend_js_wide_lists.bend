import Base

# Bend 2.0.32's JavaScript backend consumes one host stack frame per element
# in both helpers. Call append() or length() through its published loader.
def append() -> List<&2, Nat>:
  List.append(&2, Nat, List.range(20000n), [20000n])

def length() -> Nat:
  List.length(&2, Nat, List.range(20000n))
