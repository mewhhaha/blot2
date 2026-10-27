# Private common scalar declaration fixture

This scratch wrapper accepts one noncapturing public-shaped U32/Bool argument
and U32/Bool result, using arrow syntax or `Fn[static,Many,A,B]`, an explicit
empty effect row and closed resource fields. Its original source/signature are
re-recognized and projected to the existing common scalar Core; the common
shape/proof consumer and fixed Wasm target decoder independently recheck the
projected body. The exact original source remains caller-owned authority;
projected node offsets are relative to the `let` token. U32 locals, finite
scalar expressions and explicit control use the common subset; Bool locals,
loops, calls, generics, nonempty effects and multiline headers are rejected.

The isolated dispatch fixture invokes the existing generic callable path first
and preserves every accepted result's bytes and diagnostics; only a prior
rejection can reach this wrapper. Rejected sources retain the prior diagnostic,
which may be generic. The extra checking is not a compile-speed claim. Bool
inputs use a raw i32 fixture calling convention and must be 0 or 1; Bool results
are canonical only for valid inputs. The wrapper does not authenticate package
or artifact origin, validate resources, qualify C09/M13/public ABI, or expose a
public host bridge. Public commands remain gated.
