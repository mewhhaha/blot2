# Private cross-module scalar interface fixture

This slice builds a fresh descriptor-root source graph and independently
rechecks each import edge against its source alias and normalized target path.
It supports one private U32-to-U32 entry declaration whose body is exactly a
qualified `alias.member(parameter)` call, and provider modules whose
single-line declarations are restricted scalar functions. Provider public
scalar interfaces are freshly reconstructed and independently checked against
the exact package, module path, declaration, policy and caller-supplied ABI
bytes. Private declarations never satisfy an exported-member lookup. Missing
aliases, missing public members, wrong result types, duplicate declarations,
and a caller depth above 128 are rejected. Lexical parameter/import collisions
and same-scope caller/import collisions are conservatively rejected.

Required call lookup and caller-supplied optional member probes produce ordered
positive or negative observations with exact alias, member, producer path and
canonical interface bytes when present. Missing required lookups return their
negative observation, but no successful semantic revision is published. A
trusted caller must supply any optional probes; this is not a complete K1
name-resolution or dependency-observation engine. Optional member probes are
scoped to that caller; a probe whose alias is shadowed by the parameter or
caller declaration is rejected rather than recorded as a module lookup.
Interface hashes or numeric
IDs never replace exact bytes or fresh source checking.

The sequential retained fixture re-reads and rechecks the graph on every
request. A provider body-only edit can leave the checked caller observation
unchanged if the exact public interface is unchanged. Adding a previously
missing public member, changing a contract or changing ABI bytes changes the
snapshot. Invalid source, missing exports and explicit test interruption leave
the prior successful generation active. The eight-version limit declines
retention and returns a fresh unretained result. No actual caller recompilation
is skipped, no cross-module Wasm call is emitted, and no performance claim is
made by this comparison cutoff.

This is not a complete K1 frontend, ABI profile, checked project artifact or
public compiler path. The ABI value is a caller-supplied 32-byte test input,
not an authenticated complete ABI profile. Source files are read at separate
times and the descriptor-root, filesystem mutation, unsupported-platform,
trusted session, asynchronous cancellation and OOM caveats in `project_SCHEMA.md`
and `SOURCE_RESOLVER.md` continue to apply. No full C09 work accounting or
concurrency guarantee is established.
