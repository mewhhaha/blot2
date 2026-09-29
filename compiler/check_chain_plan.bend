import Base
import ./model.bend as M
import ./groups.bend as G
import ./index.bend as Index

type Job is Data:
  Job{position: Nat, job: G.Job}

type Chain is Data:
  Chain{position: Nat, level: Nat, jobs: List<&2, Job>}

type Consumer is Data:
  Only{position: Nat}
  Several{}

type Parent is Data:
  NoParent{}
  OneParent{position: Nat}
  SeveralParents{}

type Linked is Data:
  Linked{position: Nat, job: G.Job, parent: Parent}

type Relations is Data:
  Relations{parent: Parent, consumers: Map<&2, Consumer>}

type Topology is Data:
  Topology{jobs: List<&2, Linked>, consumers: Map<&2, Consumer>}

def required(-V: Data, found: Maybe<&2, V>, name: String) -> Result<&2, &2, M.Diagnostic, V>:
  match found:
    case Some{value}:
      Done{value}
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "incremental plan omitted a required checked dependency"}}

def publish(names: List<&2, String>, +value: Nat, indexed: Map<&2, Nat>) -> Map<&2, Nat>:
  match names:
    case Nil{}:
      indexed
    case name <> tail:
      publish(tail, value, Index.set(Nat, indexed, name, value))

def parent_with(previous: Parent, +position: Nat) -> Parent:
  match previous:
    case NoParent{}:
      OneParent{position}
    case OneParent{prior}:
      Bool.pick(Parent, Nat.is_eq(prior, position), OneParent{position}, SeveralParents{})
    case SeveralParents{}:
      SeveralParents{}

def consumer_with(previous: Maybe<&2, Consumer>, +position: Nat) -> Consumer:
  match previous:
    case None{}:
      Only{position}
    case Some{Only{prior}}:
      Bool.pick(Consumer, Nat.is_eq(prior, position), Only{position}, Several{})
    case Some{Several{}}:
      Several{}

def dependencies(names: List<&2, String>, +position: Nat, +owners: Map<&2, Nat>, relations: Relations) -> Result<&2, &2, M.Diagnostic, Relations>:
  match names:
    case Nil{}:
      Done{relations}
    case +name <> tail:
      Relations{parent, +consumers} = relations
      do Result<&2, &2, M.Diagnostic, Relations>:
        +owner : Nat <- required(Nat, Index.find(Nat, owners, name), name)
        +key : String = Nat.show(owner)
        consumer : Consumer = consumer_with(Index.find(Consumer, consumers, key), position)
        dependencies(tail, position, owners, Relations{parent_with(parent, owner), Index.set(Consumer, consumers, key, consumer)})

def relation_parent(related: Relations) -> Parent:
  Relations{parent, consumers} = related
  parent

def relation_consumers(related: Relations) -> Map<&2, Consumer>:
  Relations{parent, consumers} = related
  consumers

def topology(jobs: List<&2, G.Job>, +position: Nat, +owners: Map<&2, Nat>, consumers: Map<&2, Consumer>, reversed: List<&2, Linked>) -> Result<&2, &2, M.Diagnostic, Topology>:
  match jobs:
    case Nil{}:
      Done{Topology{List.reverse(&2, Linked, reversed), consumers}}
    case +job <> tail:
      G.Job{members, names, types} = job
      do Result<&2, &2, M.Diagnostic, Topology>:
        +related : Relations <- dependencies(names, position, owners, Relations{NoParent{}, consumers})
        topology(tail, 1n+position, publish(members, position, owners), relation_consumers(related), Linked{position, job, relation_parent(related)} <> reversed)

def sole_consumer(found: Maybe<&2, Consumer>, position: Nat) -> Bool:
  match found:
    case Some{Only{expected}}:
      Nat.is_eq(expected, position)
    case _:
      False{}

def continuation(parent: Parent, position: Nat, consumers: Map<&2, Consumer>) -> Maybe<&2, Nat>:
  match parent:
    case OneParent{+owner}:
      Bool.pick(Maybe<&2, Nat>, sole_consumer(Index.find(Consumer, consumers, Nat.show(owner)), position), Some{owner}, None{})
    case _:
      None{}

def highest_level(names: List<&2, String>, +levels: Map<&2, Nat>, maximum: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match names:
    case Nil{}:
      Done{maximum}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, Nat>:
        level : Nat <- required(Nat, Index.find(Nat, levels, name), name)
        highest_level(tail, levels, Nat.max(maximum, 1n+level))

def append_job(previous: Chain, position: Nat, job: G.Job) -> Chain:
  Chain{first, level, jobs} = previous
  Chain{first, level, Job{position, job} <> jobs}

def next_chain(parent: Maybe<&2, Nat>, +position: Nat, +job: G.Job, heads: Map<&2, Nat>, chains: Map<&2, Chain>, levels: Map<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Chain>:
  match parent:
    case Some{owner}:
      do Result<&2, &2, M.Diagnostic, Chain>:
        head : Nat <- required(Nat, Index.find(Nat, heads, Nat.show(owner)), "chain head")
        previous : Chain <- required(Chain, Index.find(Chain, chains, Nat.show(head)), "dependency chain")
        return append_job(previous, position, job)
    case None{}:
      G.Job{members, names, types} = job
      do Result<&2, &2, M.Diagnostic, Chain>:
        level : Nat <- highest_level(names, levels, 0n)
        return Chain{position, level, [Job{position, job}]}

def chain_le(left: Chain, right: Chain) -> Bool:
  Chain{a, +x, first} = left
  Chain{b, +y, second} = right
  Bool.or(Nat.is_lt(x, y), Bool.and(Nat.is_eq(x, y), Nat.is_le(a, b)))

def ordered_jobs(chains: List<&2, Chain>) -> List<&2, Chain>:
  match chains:
    case Nil{}:
      Nil{}
    case Chain{position, level, jobs} <> tail:
      Chain{position, level, List.reverse(&2, Job, jobs)} <> ordered_jobs(tail)

# Contract only single-consumer edges whose child depends on that SCC alone.
# Fan-outs and joins remain visible, and each SCC still checks separately.
def chain_head(chain: Chain) -> Nat:
  Chain{position, level, jobs} = chain
  position

def chain_level(chain: Chain) -> Nat:
  Chain{position, level, jobs} = chain
  level

def build(jobs: List<&2, Linked>, +consumers: Map<&2, Consumer>, +heads: Map<&2, Nat>, +chains: Map<&2, Chain>, +levels: Map<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Chain>>:
  match jobs:
    case Nil{}:
      Done{List.sort(~Chain, ~chain_le, ordered_jobs(Map.values(&2, Chain, chains)))}
    case Linked{+position, +job, parent} <> tail:
      G.Job{members, names, types} = job
      do Result<&2, &2, M.Diagnostic, List<&2, Chain>>:
        +chain : Chain <- next_chain(continuation(parent, position, consumers), position, job, heads, chains, levels)
        +head : Nat = chain_head(chain)
        build(tail, consumers, Index.set(Nat, heads, Nat.show(position), head), Index.set(Chain, chains, Nat.show(head), chain), publish(members, chain_level(chain), levels))

def build_topology(linked_plan: Topology) -> Result<&2, &2, M.Diagnostic, List<&2, Chain>>:
  Topology{linked, consumers} = linked_plan
  build(linked, consumers, Map.new(&2, Nat), Map.new(&2, Chain), Map.new(&2, Nat))

def plan(jobs: List<&2, G.Job>) -> Result<&2, &2, M.Diagnostic, List<&2, Chain>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Chain>>:
    linked_plan : Topology <- topology(jobs, 0n, Map.new(&2, Nat), Map.new(&2, Consumer), Nil{})
    build_topology(linked_plan)

type Frontier is Data:
  Frontier{ready: List<&2, Chain>, pending: List<&2, Chain>}

def same_level(chains: List<&2, Chain>, level: Nat) -> Bool:
  match chains:
    case Nil{}:
      False{}
    case Chain{position, next, jobs} <> tail:
      Nat.is_eq(level, next)

def take_frontier(chains: List<&2, Chain>, +level: Nat, reversed: List<&2, Chain>, same: Bool) -> Frontier:
  match chains same:
    case remaining False{}:
      Frontier{List.reverse(&2, Chain, reversed), remaining}
    case Nil{} True{}:
      Frontier{List.reverse(&2, Chain, reversed), Nil{}}
    case chain <> +tail True{}:
      take_frontier(tail, level, chain <> reversed, same_level(tail, level))

def next_frontier(chains: List<&2, Chain>) -> Frontier:
  match chains:
    case Nil{}:
      Frontier{Nil{}, Nil{}}
    case Chain{position, +level, jobs} <> tail:
      take_frontier(Chain{position, level, jobs} <> tail, level, Nil{}, True{})
