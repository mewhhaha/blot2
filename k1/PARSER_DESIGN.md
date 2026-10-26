# Provisional parser design

This is a design sketch for a future general K1 parser, not a grammar,
completion implementation, portable format, or claim of issue #37 completion.
The private scalar fixture and current lexer are separate prototypes.

Own each module's validated UTF-8 bytes and token, node and child arrays in a
module arena; store half-open byte spans and checked owner-local indices, never
borrowed solver pointers. Preserve expression, statement, pattern, type, suite,
import and declaration tags, source order, grouping and tuple-call distinctions.
The future parser must preserve lexical control targets and must not synthesize
returns from tail expressions. Its completion pass must reject every reachable
normal function path without explicit return, every value-block path without
`break value`, and non-Unit expression statements. A return operand can itself
transfer control; an inner return prevents the pending outer transfer.

Resolve targets against distinct function, value-block, loop and owned-body
contexts. Entering a function resets all control contexts. Return targets its
nearest function; a valued break targets the nearest lexical value block. Bare
break and continue target a non-carry loop; next and stop target a carry loop.
Seal and abort target owned construction. An if, case arm or loop suite is not
a value-block target. A target that is missing or incompatible is
`k1_bad_control_target`. Affine/loan cleanup across transfers remains a later
semantic judgment; a syntactic target is not evidence that a transfer is safe.

Enforce the specified 16 MiB module source bound, syntactic nesting 64, and
4,096 modules / 65,536 import edges before resource-dependent recursion and
while traversing the import graph. Check span/table arithmetic before allocation
and charge semantic visits to their separate normative budget. Process OOM is
not a source-limit or semantic-budget diagnostic. Exact syntax-depth accounting,
lexer/parser interface and declaration recovery must be frozen before parser
admission; this prototype does not establish them. The parser must check the
combined syntax nesting against 64, not independently permit 64 delimiters
plus 64 indentation levels. Quotes are admitted only for module metadata,
not arbitrary strings. Import resolution rejects absolute paths, parent escapes
and symlink escapes from the configured package root.

Parse each immutable source snapshot with isolated scratch and deterministic
owner-local node numbering. Resolve package-root confinement, aliases, import
cycles, and dependencies deterministically before scheduling; parallel work
uses independent jobs and completed immutable interfaces without shared mutable
solver state. Commit a revision only after required validation succeeds.

When durable artifacts are designed, include explicit versioned tags,
length-delimited data, fixed-endian integers, canonical local IDs and sorted
external references, source/module and package-root identity, exact policy and
ABI versions, and positive and negative dependency observations. Keep source
origins separately keyed. Validate all lengths, indices, scope and target
relationships before use. BLAKE3 hashes select candidates, not authority;
untrusted work receipts cannot skip required admission, and externally supplied
executable bytes must be rebuilt or independently authorized. AST structure
alone cannot establish type, effect, proof, region, or lifetime safety.

`syntax.goose` is only a finite owned structural model used to test spans,
parent/acyclic reference ordering and lexical targets. It models a single declaration and bounds its scratch using the 1,048,576
semantic-visit ceiling: each stored node consumes at least one visit. This is
not a per-module source acceptance limit or a shared compiler work receipt. It checks
parent-contained byte spans but not UTF-8 or token boundaries, sibling order,
or permitted parent/child kinds. It is neither a general AST nor an independent
validator of source grammar, semantic contracts, or artifacts.
