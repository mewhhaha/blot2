# Private checked unsigned constant offsets

The source-bound scalar/loop path accepts an unsigned constant addition only
when independently replayed evidence proves that the exact guarded alias has
an upper bound whose sum with the offset fits U32. Guard polarity, alias paths,
predecessor joins and loop fact resets are checked against the retained source.
The producer and verifier use U64 arithmetic for the bound calculation.

The search retains its first reachable fact rather than choosing the tightest,
so it can reject safe programs. This is a bounded private proof rule, not a
general interval or loop solver, public ABI, complete K1 proof system or C09
qualification. See the validation evidence in `LEDGER.md`.
