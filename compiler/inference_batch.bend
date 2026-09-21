import Base

type Weighted<-V: Data> is Data:
  Weighted{value: V, cost: Nat}

type Partition<-V: Data> is Data:
  Partition{left: List<&2, Weighted<V>>, right: List<&2, Weighted<V>>, left_cost: Nat, right_cost: Nat}

type Batch<-V: Data> is Data:
  Sequential{tasks: List<&2, Weighted<V>>}
  Parallel{left: Batch<V>, right: Batch<V>}

def total_cost(-V: Data, tasks: List<&2, Weighted<V>>, total: Nat) -> Nat:
  match tasks:
    case Nil{}:
      total
    case Weighted{value, cost} <> tail:
      total_cost(V, tail, Nat.add(total, cost))

def cut_before(-V: Data, tasks: List<&2, Weighted<V>>, +left_cost: Nat, +target: Nat) -> Bool:
  match tasks:
    case Nil{}:
      True{}
    case Weighted{value, cost} <> tail:
      +after = Nat.add(left_cost, cost)
      Bool.and(Nat.is_gt(left_cost, 0n), Bool.or(Nat.is_ge(left_cost, target), Bool.and(Nat.is_ge(after, target), Nat.is_le(Nat.sub(target, left_cost), Nat.sub(after, target)))))

def partition(-V: Data, tasks: List<&2, Weighted<V>>, reversed: List<&2, Weighted<V>>, +left_cost: Nat, +total: Nat, +target: Nat, reached: Bool) -> Partition<V>:
  match tasks reached:
    case Nil{} _:
      Partition{List.reverse(&2, Weighted<V>, reversed), Nil{}, left_cost, 0n}
    case remaining True{}:
      Partition{List.reverse(&2, Weighted<V>, reversed), remaining, left_cost, Nat.sub(total, left_cost)}
    case Weighted{value, +cost} <> +tail False{}:
      +next = Nat.add(left_cost, cost)
      partition(V, tail, Weighted{value, cost} <> reversed, next, total, target, cut_before(V, tail, next, target))

def forkable(-V: Data, parts: Partition<V>, +grain: Nat) -> Bool:
  Partition{left, right, +left_cost, +right_cost} = parts
  Bool.and(Nat.is_gt(left_cost, 0n), Bool.and(Nat.is_gt(right_cost, 0n), Bool.and(Nat.is_ge(left_cost, grain), Nat.is_ge(right_cost, grain))))

def batches(-V: Data, +fuel: Nat, parts: Partition<V>, +grain: Nat, parallel: Bool) -> Batch<V>:
  match fuel parts parallel:
    case 1n+rest Partition{+left, +right, +left_cost, +right_cost} True{}:
      +left_parts = partition(V, left, Nil{}, 0n, left_cost, Nat.div(left_cost, 2n), False{})
      +right_parts = partition(V, right, Nil{}, 0n, right_cost, Nat.div(right_cost, 2n), False{})
      a = batches(V, rest, left_parts, grain, forkable(V, left_parts, grain))
      b = batches(V, rest, right_parts, grain, forkable(V, right_parts, grain))
      Parallel{a, b}
    case _ Partition{left, right, left_cost, right_cost} _:
      Sequential{List.reverse.go(&2, Weighted<V>, List.reverse(&2, Weighted<V>, left), right)}

def plan(-V: Data, +tasks: List<&2, Weighted<V>>, +grain: Nat) -> Batch<V>:
  +total = total_cost(V, tasks, 0n)
  +parts = partition(V, tasks, Nil{}, 0n, total, Nat.div(total, 2n), False{})
  batches(V, List.length(&2, Weighted<V>, tasks), parts, grain, forkable(V, parts, grain))

def run_leaf(~V: Data, ~C: Data, ~R: Data, ~run: V -> C -> R, tasks: List<&2, Weighted<V>>, +context: C, reversed: List<&2, R>) -> List<&2, R>:
  match tasks:
    case Nil{}:
      List.reverse(&2, R, reversed)
    case Weighted{value, cost} <> tail:
      run_leaf(~V, ~C, ~R, ~run, tail, context, run(value, context) <> reversed)

def join(-R: Data, left: List<&2, R>, right: List<&2, R>) -> List<&2, R>:
  List.reverse.go(&2, R, List.reverse(&2, R, left), right)

def execute(~V: Data, ~C: Data, ~R: Data, ~run: V -> C -> R, batch: Batch<V>, +context: C) -> List<&2, R>:
  match batch:
    case Sequential{tasks}:
      run_leaf(~V, ~C, ~R, ~run, tasks, context, Nil{})
    # Match Bend's coarse lane assignment without changing weighted grain cuts.
    case Parallel{Parallel{Parallel{a, b}, Parallel{c, d}}, Parallel{Parallel{e, f}, Parallel{g, h}}}:
      ra rb rc rd re rf rg rh = execute(~V, ~C, ~R, ~run, a, context) execute(~V, ~C, ~R, ~run, b, context) execute(~V, ~C, ~R, ~run, c, context) execute(~V, ~C, ~R, ~run, d, context) execute(~V, ~C, ~R, ~run, e, context) execute(~V, ~C, ~R, ~run, f, context) execute(~V, ~C, ~R, ~run, g, context) execute(~V, ~C, ~R, ~run, h, context)
      join(R, join(R, join(R, ra, rb), join(R, rc, rd)), join(R, join(R, re, rf), join(R, rg, rh)))
    case Parallel{Parallel{a, b}, Parallel{c, d}}:
      ra rb rc rd = execute(~V, ~C, ~R, ~run, a, context) execute(~V, ~C, ~R, ~run, b, context) execute(~V, ~C, ~R, ~run, c, context) execute(~V, ~C, ~R, ~run, d, context)
      join(R, join(R, ra, rb), join(R, rc, rd))
    case Parallel{left, right}:
      a b = execute(~V, ~C, ~R, ~run, left, context) execute(~V, ~C, ~R, ~run, right, context)
      join(R, a, b)
