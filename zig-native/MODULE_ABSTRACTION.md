# Module abstraction

This specifies module visibility, abstraction and wrapper erasure. See
[implementation qualification](MODULE_ABSTRACTION_QUALIFICATION.md) for the
implemented representation and its limits, and the
[guide](../compiler/guide.md#modules-constants-current-limits) for Source
behavior.

## Declarations and names

Keep existing declarations public by default. Add one visibility modifier,
`private`, before a declaration. It applies to values, transparent aliases,
data, contracts and effect families. Constructors and operations inherit their
declaration's visibility. Imports introduce names in their importing module;
they do not become re-exports automatically.

```blot
private const offset = 7
private type Internal = { value: U32 }
const answer: U32 = offset
entry const main = answer
```

`entry` continues to control guest exports from the project's entry module. It
does not grant module visibility. `private entry const main = answer` is legal:
the host can invoke main, while another Blot module cannot import it. `private`
precedes `entry`; repeated or misplaced modifiers reject at the modifier. No
public modifier or export list is required for existing programs. Imported
modules retain the existing prohibition on entry declarations. The new words
`private`, `opaque` and `export` are contextual at declaration starts; ordinary
identifier uses remain legal. Privacy introduces no runtime check.

An importer can see only the producer's public names through named or namespace
imports. A namespace exposes that public table, including public types,
constructors, contracts, operations and associated declarations. Existing
lexical receiver precedence remains unchanged. Private names are available
through ordinary lookup inside their defining module. Another module does not
gain access by sharing a directory, namespace alias, dependency bundle or
checkpoint.

Add selective re-exports:

```blot
export { answer as forwarded, Token } from "./producer"
```

The statement introduces public forwarding names in this module and resolves
only against the producer's public table. Names without `as` keep their
spelling. Values, types, constructors, contracts and effect families retain
their declaration kind and original identity. Exporting a type does not export
its differently named constructors or associated declarations. Those require
their own forwarding names. Namespace-wide/star re-exports and whole-namespace
re-exports are outside this initial syntax.

A local declaration or another forwarding declaration with the same name is a
duplicate declaration, including two aliases of the same original declaration.
Forwarding never creates a new nominal identity, implementation or constructor.
The defining module may intentionally expose a function referring to a private
value, for example `const answer = offset`; that exports answer's checked value,
not the private name or any private type identity.

Re-export dependencies obey the existing 4,096-module acquisition bound and
cycle rejection. Resolve forwarding names by producer identity, without
enumerating import paths, within a shared one-million-transition resolution
budget. Ambiguous producers, duplicate names or budget exhaustion reject
deterministically. Errors retain the requesting export/import span and related
producer locations.

## Opaque representations

Add an opaque nominal declaration, with the existing type-parameter syntax:

```blot
opaque type Token = U32
opaque type Box a = { value: a }
private opaque type InternalToken = U32
```

The right side is an ordinary checked representation type. Token and Box are
nominal identities, distinct from their representations and from same-spelled
types in other modules. Neither defining-module use nor an alias implicitly
coerces a Token to U32. Quantified type and effect-row parameters remain
explicit; an opaque declaration does not close an open row or manufacture an
effect.

Each opaque declaration supplies one private constructor with its type's name.
Use ordinary constructor application and matching inside the defining module:

```blot
opaque type Token = U32
const make: U32 -> Token = func value => return $Token value
const read: Token -> U32 = func ($Token value) => return value
```

The constructor is total over exactly the checked representation. It is always
private, even when the opaque type is public. It cannot be named in an import or
re-export. Public factory/observer functions deliberately grant construction or
observation without exposing that constructor. There is no unchecked cast,
representation selector, inferred conversion or separate unwrap intrinsic.

Inside the defining module, existing nominal-field projection can inspect the
representation's common fields. Outside, representation fields and constructor
patterns are unavailable. A public associated declaration on the opaque owner
can supply an operation to clients through the usual dispatch rules; private
associated declarations cannot participate in external evidence selection.
Importers cannot derive equality, arithmetic, iteration or field evidence from
the representation. Public contracts, associated operations and effect
relationships supply only the evidence they explicitly declare.

Transparent aliases preserve opacity:

```blot
import { Token } from "./tokens"
type LocalToken = Token
```

LocalToken has Token's identity and access rules. It introduces no constructor.
Passing the type as a compile-time witness likewise exposes its public identity,
parameters and public relationships; reflection cannot reveal the representation
or private constructors/fields. Associated type members added by later tasks
must apply the same public/private checks to their identities and equations.

A public value/type/contract/effect signature cannot mention an unexported
private nominal identity, constructor, operation or predicate implementation.
Reject such an escaping private identity at the public declaration. The hidden
representation of a public opaque type is the explicit exception: it belongs to
the producer's private implementation, and public signatures mention only the
opaque identity. A public function may contain private code and constants; its
checked public signature must remain usable without private semantic access.

## Identity and separate compilation

The portable identity of a module declaration is its canonical producer path,
declaration kind and original declaration name. Local unit/AST indexes are
relocated handles for that identity. Unrelated declaration insertion, private
body edits and re-export renaming do not create a new opaque identity. Renaming
the defining declaration or changing its producer path does. Public arity,
parameter kinds and contracts are checked interface facts, rather than ordinal
or source-offset identity. Alpha-renaming parameters does not change them.

Public semantic interfaces contain visible names, forwarding targets, public
schemes/requirements, abstract nominal identities and declared public
relationships. Opaque representations, their constructors, payload type graphs
and field names are absent from the importer-visible interface. Private
declarations are absent too. Validation rejects forged forwarding kinds,
inconsistent producer ownership, private references in public signatures,
duplicate identities and incompatible definitions of the same identity.

Code generation also needs an exact storage contract. An opaque type publishes
an ABI descriptor with machine-word shape, size/alignment and typed ownership
roles, without a source representation type or selectable field names. The
producer checks that descriptor against its representation. An importer may use
the descriptor for calls, storage, copying and destruction, never as semantic
field/type/effect evidence. Unresolved generic layouts retain ordinary
specialization or conservatively decline reuse.

Dependency archives distinguish public semantic interfaces, storage contracts
and private executable owners. A compiler may retain the producer's private Core
for specialization and code generation; importing that archive cannot promote
its private catalog into public lookup or expose opaque payload graphs through
completion, diagnostics or reflection. The private owner remains exact and
validated under [the ownership contract](CONTRACT.md) and
[semantic-artifact admission](SEMANTIC_ARTIFACTS.md). Archives are executable
artifacts; language visibility is enforced by those interfaces and owner checks.

Version every changed dependency/interface/checkpoint schema and its settings
key. In-process, dependency-loaded and restarted projects use the same public
view. Old artifacts decline admission and rebuild; no partial decoder guesses
visibility or reconstructs a missing opaque layout. Candidate failure/OOM must
leave the old revision and its source, interface and executable owners intact.

## Semantic cutoffs and executable dependencies

Separate three exact inputs:

1. The public semantic interface: visibility, stable identities, public types,
   obligations and relationships.
2. The machine storage contract, including ownership roles.
3. Private executable dependencies actually read by inlining, specialization,
   constants and staged construction.

A private body edit with all public interface facts unchanged must reuse a
semantic caller. Private representation edits with the same abstract interface
also preserve semantic reuse. A changed storage contract invalidates affected
layout/call code. Reading or inlining an edited private body invalidates its
executable consumer even when that consumer's checked semantics reuse. A
representation edit that changes neither interface nor storage still invalidates
an executable consumer that read it. This is task 024's general body/interface
cutoff, with explicit visibility and opaque identities.

Changing a public scheme, predicate, effect relationship, visibility, forwarding
target, arity or identity must resume affected semantic checking. A source edit
and the corresponding dependency-artifact replacement must make the same
decision. Hashes locate candidates; exact owned facts validate reuse. Public
interface equality never certifies private executable equality.

### Import and edit examples

The following proposed modules give direct, namespace and forwarding clients the
same public identity:

```blot
// tokens.blot
opaque type Token = U32
private const offset = 1
const make: U32 -> Token = func value => return $Token (value + offset)
const read: Token -> U32 = func ($Token value) => return value

// facade.blot
export { Token as Ticket, make, read } from "./tokens"

// outward.blot
export { Ticket, make, read } from "./facade"

// main.blot
import { Token, make, read } from "./tokens"
import * as facade from "./outward"
const direct: Token = make 41
const forwarded: facade.Ticket = direct
entry const answer = facade.read forwarded
```

The result is 42. Importing offset, importing/re-exporting the hidden Token
constructor, matching `$Token` in main, or passing 42 where Ticket is expected
must reject at that use. A different module's `opaque type Token = U32` remains
a distinct type, even through a same-spelled forwarding alias.

Changing offset from 1 to 2 preserves each public semantic interface and must
reuse main's checked semantics. Rebuild executable readers of make so fresh,
retained, dependency-loaded and restarted clients all return 43. Changing read
to return F32 changes its public scheme and must recheck the client. Replacing
Token's representation with a reference-bearing record preserves its abstract
identity, while changed storage/ownership facts invalidate machine consumers.
Failure while preparing either edit preserves the complete prior revision.

## Wrapper erasure

An opaque value has exactly its checked representation's runtime storage and
ownership roles. Its single hidden constructor adds no tag, allocation, pointer
or indirection. Construction and matching are representation operations with
erased nominal proof. Type checking continues to distinguish Token from U32
after optimization. This applies to ordinary user modules without recognizing
type names or producer paths.

Scalar Token/U32 wrappers must have identical machine parameter/result shape and
storage operations. Generic record and reference representations inherit their
representation's allocations, ownership, aliasing and effect order; wrapping
them must add none. This does not eliminate allocations required by the
representation itself. Ordinary multi-constructor data remains ordinary data;
its tags and branching are not erased by this rule.

Task 053 compares wrapped/unwrapped operation bodies and allocation traffic,
including imports, portable dependencies, captured/returned values and retained
edits. Whole Wasm byte equality is required only where public nominal metadata
and export identity are deliberately held equal. Otherwise compare the exact
machine bodies/layouts, guest results, traps, effects and memory counters.

## Acceptance laws

The tests below are requirements for 052–053, not observed compiler behavior:

| Producer/client change                                                       | Required result                                                                            |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Existing modules with no new syntax                                          | Same visibility, diagnostics, type graphs and guest behavior                               |
| Import public make/read/Token and round-trip 42                              | Result 42; no wrapper allocation/tag; Token remains distinct from U32                      |
| Import private constructor or access opaque payload field                    | Positioned private-access error; no payload graph in details/completion                    |
| Match `$Token` in an importer, alias or re-export client                     | Private-access error at the constructor use                                                |
| Namespace alias and two re-export hops                                       | Same producer identity and privacy; no constructor imported with the type                  |
| Two producer modules each declare opaque Token                               | Their values fail to unify; same spelling never merges identities                          |
| Export a signature mentioning private InternalToken                          | Reject private identity escape before publication                                          |
| Export/import private effect operation or select private associated evidence | Reject; no fallback to hidden evidence                                                     |
| Unrelated/private declaration inserted before Token                          | Identity/public interface preserved; semantic callers reuse                                |
| Private read body changed while signature stays fixed                        | Semantic caller reuses; actual executable readers invalidate; fresh/retained output agrees |
| Private representation changed U32→F32 with public Token signatures          | Semantic callers reuse; changed machine-word shape invalidates storage/call consumers      |
| Private record field x renamed y with unchanged layout and public signatures | Semantic callers reuse; executable readers of changed private facts invalidate             |
| Representation gains a reference word                                        | Semantic interface can remain equal; ABI/ownership consumers invalidate and preserve roots |
| Public type/visibility/relationship or forwarding producer changes           | Affected semantic callers recheck; no old evidence admitted                                |
| Malformed/old artifact, failed source edit or allocator failure              | Reject/recompute without changing last-good owners or output                               |
| Re-export cycle or exhausted forwarding budget                               | Reject within fixed bounds; no partial public table published                              |

Native laws must cover interface validation, stable relocation, visibility,
owned publication and allocation failure. Executed-Wasm laws must cover source,
dependency and checkpoint clients; scalar/reference wrapper erasure; effects,
traps, alias preservation and teardown. Record fresh and retained work/CPU and
requested/live allocation against the language-evolution targets. Neither this
specification nor successful parsing completes either implementation task.

## Specification qualification

Implementation: `879a508`. Deno 2.9.7 formatting and all 25 local links/anchors
across this document and the ownership contract pass. The current guide was
reviewed for declaration parameters, constructor matching, imports, entry
exports, associated dispatch and type/effect reflection. The proposed module
examples trace direct/namespace clients, two forwarding hops, private access and
same-spelled identity rejection, and private/public edit decisions through
source, dependency and checkpoint paths. These are acceptance requirements for
052–053; this documentation supplies no executable feature or performance
measurement.
