# 051 — Specify module abstraction

## Status, dependencies, and originating requirements

- **Status:** Complete — specification qualified locally; nothing pushed.
- **Dependencies:** [020](020-persist-complete-semantic-artifacts.md)
- **Originating requirements:** LANGUAGE_EVOLUTION: Direction 2 / module
  abstraction. Sources:
  [Language evolution](../zig-native/LANGUAGE_EVOLUTION.md).
- **Execution:** Follow the
  [task order and completion rules](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/tasks/README.md#completion-rules).

## Outcome

Specify opaque representations, construction access, exports/re-exports, privacy
and nominal identity across separate compilation.

## Starting point

[compiler/guide.md](../compiler/guide.md#modules-constants-current-limits)
describes public-by-default module declarations and entry exports. Transparent
aliases and dependency interfaces exist; opaque representation boundaries do
not.

## Implementation checklist

- [x] Settle source syntax and compatibility for visibility, opaque
      declarations, construction/destruction access and selective re-exports.
- [x] Define nominal identity and what importers may observe, including aliases,
      associated members and type/effect relationships.
- [x] Specify portable interfaces and private-implementation cutoff behavior
      without leaking representation through archives.
- [x] Document positive/negative module examples and zero-cost-wrapper
      obligations for later qualification.

## Validation

Use `deno fmt --check` on the changed Markdown, validate local links, and review
the examples below against the current guide and ownership contract. This is a
documentation task; run compiler checks only if code or executable fixtures
change.

- Review direct import, namespace alias, chained re-export, same-spelled type
  and private constructor examples.
- Trace source and compiled-dependency clients before/after private
  implementation and public interface changes.

## Acceptance criteria

- [x] A durable module specification settles syntax, semantics, representation,
      diagnostics and compatibility.
- [x] Tasks 052–053 have explicit privacy laws and observable cutoff/erasure
      criteria.
- [x] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Implementation: `879a508`.
- Validation: Deno 2.9.7; `deno fmt --no-config --check` passes the module
  specification and ownership contract. All 25 local links/anchors resolve.
  Examples were reviewed against the current guide: direct/namespace imports,
  two forwarding hops, same-spelled identities, private constructors and
  source/dependency/checkpoint edit decisions have explicit positive/negative
  laws. Proposed syntax is labelled and was not treated as executable evidence.
- Comparison: documentation only; no runtime or compiler cost change is claimed.
- Remaining limitations: 052 implements syntax, public/private interfaces and
  opaque storage; 053 qualifies cutoff behavior and wrapper erasure. Private
  executable archives remain compiler-owned and validated, outside the public
  semantic view.
- Durable record: [MODULE_ABSTRACTION](../zig-native/MODULE_ABSTRACTION.md).
