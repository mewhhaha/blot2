import Base
import ./repro.bend as Repro
import ./LAWS.bend as Laws

def Laws.rebox_identity(values):
  match values:
    case Nil{}:
      {==}
    case value <> tail:
      {==}
