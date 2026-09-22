import Base
import ./repro.bend as Repro

law rebox_identity:
  for +values: List<&2, Repro.Value>
  {Repro.rebox(values) == values : List<&2, Repro.Value>}
