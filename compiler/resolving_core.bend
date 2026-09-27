import Base
import ./model.bend as M
import ./infer.bend as I
import ./groups.bend as G
import ./checked_core.bend as Core
import ./core_compare.bend as Compare
import ./dependency.bend as D
import ./index.bend as Index

# Resolving evidence is an atomic product of one exact checked SCC and the
# requirements inferred in its variable namespace. Ordinary certificates alone
# do not justify dropping deferred requirements when checking a changed module.
type Witness is Data:
  Witness{certificate: Core.Certificate, needs: List<&2, G.GroupNeeds>}

type Pairing is Data:
  Unclaimed{}
  Claimed{needs: G.GroupNeeds}
  Invalid{}

def member_names(members: List<&2, I.Binding>) -> List<&2, String>:
  match members:
    case Nil{}:
      Nil{}
    case I.Binding{name, ty, variables, predicates} <> tail:
      name <> member_names(tail)

def need_names(needs: List<&2, G.Resolution>) -> List<&2, String>:
  match needs:
    case Nil{}:
      Nil{}
    case G.Resolution{declaration, identity, dispatch, member, templates, left, right, result, invocation, ambient} <> tail:
      declaration <> need_names(tail)

def contains_all(names: List<&2, String>, +available: List<&2, String>) -> Bool:
  match names:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(D.contains(available, head), contains_all(tail, available))

def overlaps(names: List<&2, String>, +available: List<&2, String>) -> Bool:
  match names:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(D.contains(available, head), overlaps(tail, available))

def pair_claim(overlap: Bool, exact: Bool, need: G.GroupNeeds, prior: Pairing) -> Pairing:
  match overlap exact prior:
    case False{} _ prior:
      prior
    case True{} True{} Unclaimed{}:
      Claimed{need}
    case True{} _ _:
      Invalid{}

def pair_needs(needs: List<&2, G.GroupNeeds>, +names: List<&2, String>, prior: Pairing) -> Pairing:
  match needs:
    case Nil{}:
      prior
    case +need <> tail:
      G.GroupNeeds{next, requests, members, generalized} = need
      +claimed = member_names(members)
      +requested = need_names(requests)
      overlap = Bool.or(overlaps(claimed, names), overlaps(requested, names))
      exact = Bool.and(contains_all(names, claimed), Bool.and(contains_all(claimed, names), contains_all(requested, names)))
      pair_needs(tail, names, pair_claim(overlap, exact, need, prior))

def paired(pairing: Pairing, certificate: Core.Certificate) -> Maybe<&2, Witness>:
  match pairing:
    case Invalid{}:
      None{}
    case Unclaimed{}:
      Some{Witness{certificate, Nil{}}}
    case Claimed{need}:
      Some{Witness{certificate, [need]}}

def pair(+certificate: Core.Certificate, needs: List<&2, G.GroupNeeds>) -> Maybe<&2, Witness>:
  Core.Certificate{module, checked, imports} = certificate
  paired(pair_needs(needs, Core.names(module), Unclaimed{}), certificate)

def add_names(names: List<&2, String>, +witness: Witness, +indexed: Map<&2, List<&2, Witness>>) -> Map<&2, List<&2, Witness>>:
  match names:
    case Nil{}:
      indexed
    case +name <> tail:
      previous = Index.get(List<&2, Witness>, indexed, name, Nil{})
      add_names(tail, witness, Map.set(&2, List<&2, Witness>, indexed, name, witness <> previous))

def add(found: Maybe<&2, Witness>, indexed: Map<&2, List<&2, Witness>>) -> Map<&2, List<&2, Witness>>:
  match found:
    case None{}:
      indexed
    case Some{+witness}:
      Witness{Core.Certificate{module, checked, imports}, needs} = witness
      add_names(Core.names(module), witness, indexed)

# The caller supplies certificates and needs from the same successful Initial.
# An incomplete/duplicate association misses; it never fabricates empty needs.
def add_need(names: List<&2, String>, +need: G.GroupNeeds, +indexed: Map<&2, List<&2, G.GroupNeeds>>) -> Map<&2, List<&2, G.GroupNeeds>>:
  match names:
    case Nil{}:
      indexed
    case +name <> tail:
      previous = Index.get(List<&2, G.GroupNeeds>, indexed, name, Nil{})
      add_need(tail, need, Map.set(&2, List<&2, G.GroupNeeds>, indexed, name, need <> previous))

def need_index(needs: List<&2, G.GroupNeeds>, indexed: Map<&2, List<&2, G.GroupNeeds>>) -> Map<&2, List<&2, G.GroupNeeds>>:
  match needs:
    case Nil{}:
      indexed
    case +need <> tail:
      G.GroupNeeds{next, requests, members, generalized} = need
      names = Set.to_list(Set.from_list(List.append(&2, String, member_names(members), need_names(requests))))
      need_index(tail, add_need(names, need, indexed))

# Most SCCs contain one declaration. Index overlapping requirements once;
# multi-member SCCs keep the complete association check, including malformed
# claims whose member list omitted the SCC's first declaration.
def for_members(names: List<&2, String>, indexed: Map<&2, List<&2, G.GroupNeeds>>, all: List<&2, G.GroupNeeds>) -> List<&2, G.GroupNeeds>:
  match names:
    case name <> Nil{}:
      Index.get(List<&2, G.GroupNeeds>, indexed, name, Nil{})
    case _:
      all

def index_certificates(certificates: List<&2, Core.Certificate>, +needs: List<&2, G.GroupNeeds>, +by_name: Map<&2, List<&2, G.GroupNeeds>>, indexed: Map<&2, List<&2, Witness>>) -> Map<&2, List<&2, Witness>>:
  match certificates:
    case Nil{}:
      indexed
    case +certificate <> tail:
      Core.Certificate{module, checked, imports} = certificate
      relevant = for_members(Core.names(module), by_name, needs)
      index_certificates(tail, needs, by_name, add(pair(certificate, relevant), indexed))

def index(certificates: List<&2, Core.Certificate>, +needs: List<&2, G.GroupNeeds>, indexed: Map<&2, List<&2, Witness>>) -> Map<&2, List<&2, Witness>>:
  index_certificates(certificates, needs, need_index(needs, Map.new(&2, List<&2, G.GroupNeeds>)), indexed)

def matches(witness: Witness, subset: M.Module, imports: List<&2, G.Interface>) -> Maybe<&2, G.Resolving>:
  Witness{Core.Certificate{original, checked, dependencies}, needs} = witness
  # Full module equality also pins ordered nominal and operation catalogs,
  # including generic templates that ordinary ready certificates can ignore.
  Bool.pick(Maybe<&2, G.Resolving>, Bool.and(Compare.same_module(original, subset), Core.same_imports(dependencies, imports)), Some{G.Resolving{checked, needs}}, None{})

def candidates(values: List<&2, Witness>, +subset: M.Module, +imports: List<&2, G.Interface>, found: Maybe<&2, G.Resolving>) -> Maybe<&2, G.Resolving>:
  match values found:
    case _ Some{resolved}:
      Some{resolved}
    case Nil{} None{}:
      None{}
    case head <> tail None{}:
      candidates(tail, subset, imports, matches(head, subset, imports))

def lookup(indexed: Map<&2, List<&2, Witness>>, job: G.Job, subset: M.Module, imports: List<&2, G.Interface>) -> Maybe<&2, G.Resolving>:
  G.Job{members, dependencies, types} = job
  match members:
    case Nil{}:
      None{}
    case name <> tail:
      candidates(Index.get(List<&2, Witness>, indexed, name, Nil{}), subset, imports, None{})
