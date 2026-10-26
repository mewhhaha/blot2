# Proposed clarification: capacity observation on affine Dest

Status: **local proposal, not an approved specification amendment and not an
implemented operation**. Do not publish a new `Dest.capacity` borrow, admit
source based on one interpretation, or file an upstream issue on the basis of
this note. The normative sources are [K1-LANG #40](https://github.com/mewhhaha/blot2/issues/40)
and [K1-MEM #41](https://github.com/mewhhaha/blot2/issues/41).

## The ambiguity

K1-LANG §2 says:

> `.length` and `.capacity` elaborate to their observations.

The same section's evaluation and usage rule says:

> Ordinary Share arguments copy with their loans preserved; affine arguments
> move. ... Only registered observations borrow without moving: builder
> reads/length/capacity observations, plus owned.open.

K1-LANG §9.1 says:

> `Len(view)`, `Cap(builder_or_dest)`, and `Init(builder)` select the
> corresponding exact witness.

K1-LANG §4 separately says each nonconstant Nat has a recoverable runtime U32
witness, while proof evidence, Region and Domain have no runtime tag. It also
states, “Owners, remaining-space tokens, destinations, builders, Once
functions, and Owned values are affine.” M02 and M05 specify Dest's exclusive
physical range and transitions. These provisions clearly
permit a proof term about the exact destination capacity, but do not say
whether writing `.capacity` on an affine Dest is a runtime source observation
that retains the destination, or whether `Cap(dest)` is restricted to proof
elaboration / an independently bound Nat witness. The exhaustive §2 borrow
list does not name Dest.

A minimal representative source shape is:

```blot
let capacity_then_discard:
  forall [r: Region, c: Nat] =>
    Fn[static, Many, Dest[r, U32, c], U32]
      ! {} resources {depth: 1, frame: 0}
= fn dst => do:
  let n = dst.capacity
  dest.discard(dst)
  return n
```

The example is intended to isolate usage, not to assert that the current
prototype parses this generic interface. Under an ordinary affine move for the
first expression, the subsequent `dest.discard(dst)` reuses a moved value.
Under a nonmoving runtime observation, it remains usable and `n` denotes the
same exact capacity witness. The existing text does not unambiguously select
between those source judgments; equal bytes, variable names, or a `Cap` proof
term are not themselves permission to duplicate a Dest.

## Two possible minimal resolutions

**A. Register a nonmoving source observation.** Extend the exhaustive §2 list
to include `dest.capacity` and define it as a temporary read-only observation
of the exact live Dest's capacity, with no new surviving loan. It leaves the
same exclusive destination authority available after the observation, cannot
be used after that authority has moved, and cannot transport facts to another
Dest or version. The result is its existing U32 Nat witness; it is not evidence
that any element is initialized. This is a semantic change to the list of
registered observations and requires the corresponding registry entry and
positive/negative laws.

**B. Restrict Dest capacity to the proof/Nat-witness layer.** Clarify that
`Cap(dest)` is an exact ghost observation and does not itself authorize a
source-level nonmoving `.capacity` on affine Dest. Specify how a function that
needs a runtime capacity receives the already-bound Nat witness independently,
or require an explicit contract/API that transfers the Dest along with its
capacity. Under this resolution, `dst.capacity` above is rejected unless such
an explicitly specified source form applies; proofs can still use `Cap(dst)`
without manufacturing a runtime capability or permitting a second use.

Neither option is selected by this note. The implementing compiler must not
silently choose a nonmoving borrow, mint authority from descriptor words, or
assert that the example is accepted until the language contract is clarified.

## Required laws for whichever resolution is adopted

- Check the example's chosen acceptance or exact rejection in check/build,
  optimization on/off and cold/warm modes; verify no fallback to legacy.
- Show that a consumed/discarded Dest cannot subsequently be observed or used,
  and an observation of one Dest cannot authorize another same-sized Dest.
- Show that capacity never proves the initialized prefix of a Builder or View.
- If A is adopted, verify the observation executes once, does not move or
  extend the lifetime of Dest, cannot coexist with conflicting loans, and
  leaves exactly one subsequent exclusive consumption; validate the emitted
  operation's declared borrow role independently.
- If B is adopted, verify ghost facts erase while every runtime Nat witness
  needed by calls or output remains available; no hidden descriptor read is
  represented as an unregistered source-level borrow.
