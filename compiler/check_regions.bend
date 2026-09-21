import Base
import ./model.bend as M
import ./groups.bend as G
import ./check_chain_plan.bend as Chains
import ./dependency.bend as D
import ./index.bend as Index

type Region is Data:
  Region{chains: List<&2, Chains.Chain>}

def job_owners(jobs: List<&2, Chains.Job>, +head: Nat, owners: Map<&2, Nat>) -> Map<&2, Nat>:
  match jobs:
    case Nil{}:
      owners
    case Chains.Job{position, G.Job{members, dependencies, types}} <> tail:
      job_owners(tail, head, Chains.publish(members, head, owners))

def chain_owners(chains: List<&2, Chains.Chain>, owners: Map<&2, Nat>) -> Map<&2, Nat>:
  match chains:
    case Nil{}:
      owners
    case Chains.Chain{position, level, jobs} <> tail:
      chain_owners(tail, job_owners(jobs, position, owners))

def references(names: List<&2, String>, +owners: Map<&2, Nat>, found: Set()) -> Result<&2, &2, M.Diagnostic, Set()>:
  match names:
    case Nil{}:
      Done{found}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, Set()>:
        owner : Nat <- Chains.required(Nat, Index.find(Nat, owners, name), name)
        references(tail, owners, Set.add(found, Nat.show(owner)))

def job_references(jobs: List<&2, Chains.Job>, +owners: Map<&2, Nat>, found: Set()) -> Result<&2, &2, M.Diagnostic, Set()>:
  match jobs:
    case Nil{}:
      Done{found}
    case Chains.Job{position, G.Job{members, names, types}} <> tail:
      do Result<&2, &2, M.Diagnostic, Set()>:
        next : Set() <- references(names, owners, found)
        job_references(tail, owners, next)

def nodes(chains: List<&2, Chains.Chain>, +owners: Map<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  match chains:
    case Nil{}:
      Done{Nil{}}
    case Chains.Chain{position, level, jobs} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
        refs : Set() <- job_references(jobs, owners, Set.new())
        rest : List<&2, D.Node> <- nodes(tail, owners)
        return D.Node{Nat.show(position), Map.keys(&2, Unit, refs), Nil{}} <> rest

# SCCs of the symmetrized chain graph are independent dependency regions.
# Original job positions survive partitioning, so the earliest error still wins.
def undirected(nodes: List<&2, D.Node>, +incoming: Map<&2, List<&2, String>>) -> List<&2, D.Node>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{+name, refs, lambdas} <> tail:
      D.Node{name, List.append(&2, String, refs, D.neighbors(incoming, name)), Nil{}} <> undirected(tail, incoming)

def chain_index(chains: List<&2, Chains.Chain>, indexed: Map<&2, Chains.Chain>) -> Map<&2, Chains.Chain>:
  match chains:
    case Nil{}:
      indexed
    case +chain <> tail:
      chain_index(tail, Map.set(&2, Chains.Chain, indexed, Nat.show(Chains.chain_head(chain)), chain))

def select_chains(names: List<&2, String>, +indexed: Map<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, List<&2, Chains.Chain>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Chains.Chain>>:
        chain : Chains.Chain <- Chains.required(Chains.Chain, Index.find(Chains.Chain, indexed, name), name)
        rest : List<&2, Chains.Chain> <- select_chains(tail, indexed)
        return chain <> rest

def regions(components: List<&2, List<&2, String>>, +indexed: Map<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  match components:
    case Nil{}:
      Done{Nil{}}
    case names <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Region>>:
        chains : List<&2, Chains.Chain> <- select_chains(names, indexed)
        rest : List<&2, Region> <- regions(tail, indexed)
        return Region{List.sort(~Chains.Chain, ~Chains.chain_le, chains)} <> rest

def partition(+chains: List<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Region>>:
    +graph : List<&2, D.Node> <- nodes(chains, chain_owners(chains, Map.new(&2, Nat)))
    components : List<&2, List<&2, String>> <- D.components(undirected(graph, D.transpose(graph, Map.new(&2, List<&2, String>))))
    regions(components, chain_index(chains, Map.new(&2, Chains.Chain)))

# One frontier already runs concurrently. A single root also implies one
# connected region: every remaining chain reaches that root through its parents.
def plan_frontier(chains: List<&2, Chains.Chain>, frontier: Chains.Frontier) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  match frontier:
    case Chains.Frontier{ready, Nil{}}:
      Done{[Region{chains}]}
    case Chains.Frontier{root <> Nil{}, pending}:
      Done{[Region{chains}]}
    case _:
      partition(chains)

def plan(+chains: List<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  plan_frontier(chains, Chains.next_frontier(chains))
