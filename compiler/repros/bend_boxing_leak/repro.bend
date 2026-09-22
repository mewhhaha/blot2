import Base

type Value is Data:
  Scalar{number: U32}
  Pair{left: Nat, right: Nat}

def rebox(values: List<&2, Value>) -> List<&2, Value>:
  match values:
    case Nil{}:
      Nil{}
    case value <> tail:
      value <> tail
