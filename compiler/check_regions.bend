import Base
import ./model.bend as M
import ./groups.bend as G
import ./check_chain_plan.bend as Chains
import ./index.bend as Index

type Region is Data:
  Region{chains: List<&2, Chains.Chain>}

type Link is Data:
  Root{rank: Nat}
  Parent{key: String}

type Resolved is Data:
  Resolved{key: String, rank: Nat, forest: Map<&2, Link>}

def root_key(root: Resolved) -> String:
  Resolved{key, rank, forest} = root
  key

def root_rank(root: Resolved) -> Nat:
  Resolved{key, rank, forest} = root
  rank

def root_forest(root: Resolved) -> Map<&2, Link>:
  Resolved{key, rank, forest} = root
  forest

def compressed(key: String, +root: String, rank: Nat, forest: Map<&2, Link>, same: Bool) -> Resolved:
  match same:
    case True{}:
      Resolved{root, rank, forest}
    case False{}:
      Resolved{root, rank, Map.set(&2, Link, forest, key, Parent{root})}

def compress(key: String, parent: String, resolved: Resolved) -> Resolved:
  Resolved{+root, rank, forest} = resolved
  compressed(key, root, rank, forest, M.name_equal(parent, root))

def resolve(fuel: Nat, key: String, +forest: Map<&2, Link>, found: Maybe<&2, Link>) -> Result<&2, &2, M.Diagnostic, Resolved>:
  match fuel found:
    case _ None{}:
      Done{Resolved{key, 0n, forest}}
    case _ Some{Root{rank}}:
      Done{Resolved{key, rank, forest}}
    case 0n Some{Parent{parent}}:
      Fail{M.Diagnostic{"internal_error", "check_regions", "region parent chain exceeds its chain count"}}
    case 1n+rest Some{Parent{+parent}}:
      do Result<&2, &2, M.Diagnostic, Resolved>:
        root : Resolved <- resolve(rest, parent, forest, Index.find(Link, forest, parent))
        return compress(key, parent, root)

def join_roots(+left: String, left_rank: Nat, right: String, right_rank: Nat, forest: Map<&2, Link>, same: Bool, order: Cmp) -> Map<&2, Link>:
  match same order:
    case True{} _:
      forest
    case False{} LT{}:
      Map.set(&2, Link, forest, left, Parent{right})
    case False{} GT{}:
      Map.set(&2, Link, forest, right, Parent{left})
    case False{} EQ{}:
      Map.set(&2, Link, Map.set(&2, Link, forest, right, Parent{left}), left, Root{1n+left_rank})

# Union by rank and path compression find weak components without constructing
# a symmetric graph, running two SCC walks, or sorting each component again.
def unite_distinct(+fuel: Nat, +left: String, +right: String, +forest: Map<&2, Link>, same: Bool) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  match same:
    case True{}:
      Done{forest}
    case False{}:
      do Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
        +a : Resolved <- resolve(fuel, left, forest, Index.find(Link, forest, left))
        +next : Map<&2, Link> = root_forest(a)
        +b : Resolved <- resolve(fuel, right, next, Index.find(Link, next, right))
        return join_roots(root_key(a), root_rank(a), root_key(b), root_rank(b), root_forest(b), M.name_equal(root_key(a), root_key(b)), Nat.cmp(root_rank(a), root_rank(b)))

def unite(fuel: Nat, +left: String, +right: String, forest: Map<&2, Link>) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  unite_distinct(fuel, left, right, forest, M.name_equal(left, right))

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

def link_dependency(owner: Maybe<&2, Nat>, settled: Maybe<&2, Nat>, fuel: Nat, head: String, name: String, forest: Map<&2, Link>) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  match owner settled:
    case Some{position} _:
      unite(fuel, head, Nat.show(position), forest)
    case None{} Some{position}:
      Done{forest}
    case None{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "incremental plan omitted a required checked dependency"}}

def dependencies(names: List<&2, String>, +fuel: Nat, +head: String, +owners: Map<&2, Nat>, +settled: Map<&2, Nat>, forest: Map<&2, Link>) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  match names:
    case Nil{}:
      Done{forest}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
        next : Map<&2, Link> <- link_dependency(Index.find(Nat, owners, name), Index.find(Nat, settled, name), fuel, head, name, forest)
        dependencies(tail, fuel, head, owners, settled, next)

def job_links(jobs: List<&2, Chains.Job>, +fuel: Nat, +head: String, +owners: Map<&2, Nat>, +settled: Map<&2, Nat>, forest: Map<&2, Link>) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  match jobs:
    case Nil{}:
      Done{forest}
    case Chains.Job{position, G.Job{members, names, types}} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
        next : Map<&2, Link> <- dependencies(names, fuel, head, owners, settled, forest)
        job_links(tail, fuel, head, owners, settled, next)

def chain_links(chains: List<&2, Chains.Chain>, +fuel: Nat, +owners: Map<&2, Nat>, +settled: Map<&2, Nat>, forest: Map<&2, Link>) -> Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
  match chains:
    case Nil{}:
      Done{forest}
    case Chains.Chain{position, level, jobs} <> tail:
      do Result<&2, &2, M.Diagnostic, Map<&2, Link>>:
        next : Map<&2, Link> <- job_links(jobs, fuel, Nat.show(position), owners, settled, forest)
        chain_links(tail, fuel, owners, settled, next)

def ordered_regions(groups: List<&2, List<&2, Chains.Chain>>) -> List<&2, Region>:
  match groups:
    case Nil{}:
      Nil{}
    case chains <> tail:
      Region{List.reverse(&2, Chains.Chain, chains)} <> ordered_regions(tail)

def collect(chains: List<&2, Chains.Chain>, +fuel: Nat, +forest: Map<&2, Link>, +groups: Map<&2, List<&2, Chains.Chain>>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  match chains:
    case Nil{}:
      Done{ordered_regions(Map.values(&2, List<&2, Chains.Chain>, groups))}
    case +chain <> tail:
      +key = Nat.show(Chains.chain_head(chain))
      do Result<&2, &2, M.Diagnostic, List<&2, Region>>:
        +resolved : Resolved <- resolve(fuel, key, forest, Index.find(Link, forest, key))
        +root : String = root_key(resolved)
        members : List<&2, Chains.Chain> = Index.get(List<&2, Chains.Chain>, groups, root, Nil{})
        collect(tail, fuel, root_forest(resolved), Map.set(&2, List<&2, Chains.Chain>, groups, root, chain <> members))

def partition_remaining(+chains: List<&2, Chains.Chain>, settled: Map<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  +fuel = List.length(&2, Chains.Chain, chains)
  do Result<&2, &2, M.Diagnostic, List<&2, Region>>:
    forest : Map<&2, Link> <- chain_links(chains, fuel, chain_owners(chains, Map.new(&2, Nat)), settled, Map.new(&2, Link))
    collect(chains, fuel, forest, Map.new(&2, List<&2, Chains.Chain>))

def partition(chains: List<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, List<&2, Region>>:
  partition_remaining(chains, Map.new(&2, Nat))

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

type RootedPlan is Data:
  RootedPlan{prefix: List<&2, Chains.Chain>, regions: List<&2, Region>}

def prefix(plan: RootedPlan) -> List<&2, Chains.Chain>:
  RootedPlan{chains, regions} = plan
  chains

def branches(plan: RootedPlan) -> List<&2, Region>:
  RootedPlan{chains, regions} = plan
  regions

# A shared frontier connects otherwise independent branches only until it finishes.
# Partition the remaining graph without those already-satisfied edges, retaining
# real joins between unfinished branches and rejecting unknown dependencies.
def release_frontier(+ready: List<&2, Chains.Chain>, pending: List<&2, Chains.Chain>, regions: List<&2, Region>, frontier: Chains.Frontier) -> Result<&2, &2, M.Diagnostic, RootedPlan>:
  match regions frontier:
    case _ Chains.Frontier{last, Nil{}}:
      # One final batch has no downstream frontier to release independently.
      Done{RootedPlan{Nil{}, regions}}
    case Region{chains} <> Nil{} _:
      do Result<&2, &2, M.Diagnostic, RootedPlan>:
        released : List<&2, Region> <- partition_remaining(pending, chain_owners(ready, Map.new(&2, Nat)))
        return RootedPlan{ready, released}
    case _ _:
      # Independent regions must not gain a new shared frontier barrier.
      Done{RootedPlan{Nil{}, regions}}

def rooted_frontier(chains: List<&2, Chains.Chain>, frontier: Chains.Frontier) -> Result<&2, &2, M.Diagnostic, RootedPlan>:
  match frontier:
    case Chains.Frontier{+root <> Nil{}, head <> tail}:
      do Result<&2, &2, M.Diagnostic, RootedPlan>:
        regions : List<&2, Region> <- partition_remaining(head <> tail, chain_owners([root], Map.new(&2, Nat)))
        return RootedPlan{[root], regions}
    case Chains.Frontier{first <> second <> rest, +head <> +tail}:
      do Result<&2, &2, M.Diagnostic, RootedPlan>:
        regions : List<&2, Region> <- partition(chains)
        release_frontier(first <> second <> rest, head <> tail, regions, Chains.next_frontier(head <> tail))
    case _:
      do Result<&2, &2, M.Diagnostic, RootedPlan>:
        regions : List<&2, Region> <- plan(chains)
        return RootedPlan{Nil{}, regions}

def rooted_plan(+chains: List<&2, Chains.Chain>) -> Result<&2, &2, M.Diagnostic, RootedPlan>:
  rooted_frontier(chains, Chains.next_frontier(chains))
