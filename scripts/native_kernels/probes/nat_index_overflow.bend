import Base
import ../../../compiler/nat_index.bend as N

def last_key() -> Nat:
  +highest = Nat.mul(16777216n, 8388608n)
  Nat.add(highest, Nat.sub(highest, 1n))

def show_found(found: Maybe<&2, U32>) -> IO(Unit):
  match found:
    case Some{value}:
      IO.print(U32.show(value))
    case None{}:
      IO.print("none")

def main() -> IO(Unit):
  +index = N.set(U32, N.new(U32), last_key(), 7)
  # The next Nat is bit 49 and must trigger Bend's Nat48 saturation/error.
  too_large = Nat.add(last_key(), 1n)
  show_found(N.find(U32, index, too_large))
