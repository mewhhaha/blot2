# Checker ownership

`check.zig` owns the current source judgment. Its `Engine` keeps chronological
type and row state, lexical scopes, diagnostics, and unpublished checked facts.
`CatalogIndex` owns nineteen temporary name/identity lookup maps. These indices
borrow declaration IDs and are destroyed without publishing mutable map storage.

`check_scheme_import.Copier` owns a single principal-graph import transaction:
type/row/operation maps, fresh quantified variables, and relocated private
scopes. It borrows an immutable source and the current destination solver.
Physical instances, Task binding versions, quantifier qualification spans,
record spellings, and actual Source binders retain explicit relocation routes.
Import never carries an old mutable solver or selected proof as authority.

Module header construction and Source/body validation are separate ordered
phases. Expression checking retains one depth guard and final fact publication;
individual rules own their original lexical cleanup scopes. Application keeps
intrinsic permission active while its ordinary invocation rule runs. Scheme
generalization separates candidate selection, connected variable/row closure,
and residual requirement publication without changing query order.

The lifecycle coordinator still owns allocation guards and final `Checked`
publication. Its current 417 lines are visible; no completion claim hides that
remaining size. Source/header validation stays separate from retained body
replay and immutable Core admission.

The 15 October focused comparison records 210 to 192 Engine fields, expression
dispatch 476 to 46 lines, statement dispatch 200 to 18, scheme generalization
206 to 129, and module header/body phases of 97/110 lines. Before/after Wasm,
ordered diagnostics, native work, and portable owner payload agree across fresh,
edit, revert, invalid-edit repair, and restart. Ordinary Cost stays 12,902 bytes
with identical requested allocation, allocation count, peak memory and zero live
bytes. These are structural and ownership checks; CPU qualification and the
final common compiler gate remain required.

Exact source/executable pins, comparisons, native allocation-failure laws,
executed guests, interface compilation and analyzer logs are in
`build/bench/finish-rest-20261015/checker-owners/`. The existing prefix snapshot
law also checks the contents of actual auxiliary body owners, preserving strict
generic rejection of borrowed pointers.

The [19 October cloud gate](CLOUD_QUALIFICATION.md) reruns the complete current
native and guest suites. The 407-line lifecycle count belongs to the earlier
split checkpoint; later checker work brings it to 417. This remaining
coordinator is an explicit size exception, not a forwarding wrapper counted as a
reduced implementation.
