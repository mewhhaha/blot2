import Base
import ./repro.bend as Repro

def input() -> IO(Nat):
  import "./probe.c"

def observe(count: Nat) -> IO(Unit):
  import "./probe.c"

def choose(mode: Nat) -> Repro.Value:
  match mode:
    case 0n:
      Repro.Scalar{7}
    case 1n+rest:
      Repro.Pair{rest, 0n}

def repeat(rounds: Nat, +mode: Nat) -> IO(Unit):
  match rounds:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        observe(List.length(&2, Repro.Value, Repro.rebox([choose(mode)])))
        repeat(rest, mode)

def main() -> IO(Unit):
  do IO<Unit>:
    mode : Nat <- input()
    repeat(4n, mode)
