# Private lexical predicate callable dispatch

This source-bound candidate accepts the existing public-shaped U32-to-Bool
arrow or `Fn[static,Many,U32,Bool]` signature with an explicit empty effect
row and bounded decimal resource fields. The retained original source and
header are independently replayed, projected to a private lexical `let` body,
and checked by the predflow source/type/completion and branch-evidence
consumers. The emitted fixed-profile target is independently decoded before
return. Checked arithmetic is not admitted without the existing bounded proof.

The dispatcher preserves the prior simple predicate path first, including its
output bytes and private failure categories. Only an earlier rejected source can
reach the lexical predicate fallback. Unsupported forms fail without bytes.
Rejected lexical programs keep the earlier predicate diagnostic, which may be
a generic unsupported/syntax status rather than a more specific lexical error.
The fallback adds source checking work; no compiler speed benefit is claimed.
Returned Bool is canonical 0/1 and this fixture's raw export is not a host ABI.
There is no complete common IR, call/effect checking, resource proof, public
artifact or ABI, M13, complete C09 or public compilation admission.
