# Private source-linked I08 transition schema

This private experiment binds a verified `i08_link_core::Program` and
source-local `i08_affine_core::Plan` to six conditional steps: fixed header
precondition `Le(n,c)`, entry invariant `Init(b)=i`, active loop edge `i<n`,
append-space derivation, simultaneous append/next carry substitution, and
natural loop exhaustion/freeze. Producer and separate consumer check the exact
source, AST sites, affine shape, job events, source proof records, role IDs,
versions and dependencies. A changed source, stop/early-return branch, wrong
invariant, wrong loop bound or forged role/version/evidence rejects.

Step 5 is an inductive invariant-preservation rule, not evidence that an
append executed. Step 6 also covers a zero-trip loop: the entry invariant
holds at `i = n = 0` without applying the preservation rule.

The proof is conditional on the append intrinsic implementing its declared
one-element initialized-prefix transition. Builder header, append-output and
result version IDs are job-local symbolic *roles*, not dynamically fresh
per-iteration versions or runtime handles. A future typed CFG must instantiate
fresh iteration versions and prove invariant substitution at each backedge;
actual append storage, initialized input, live View loan, output exclusivity,
backing disjointness, representable index arithmetic, generative Domain,
completion beyond the canonical loop, C09 and host ABI remain separate
obligations. No authority to run code is conferred by this schema.

The focused execution test first checks this conditional schema and then calls
the existing independently checked private job worker, exercising zero and
nonempty rows. This is a test-harness composition, not a new public compiler
entry or a verified connection to caller-owned runtime capabilities. The
bounded existing source-link frontend restricts row expressions to its supported
field/dt F32 grammar.

The separate private live-target test gate can emit other valid expression
variants, but the current JS live-authority wrapper authenticates only the
canonical pinned module bytes. Other targets need a separately verified
target-binding seam before that wrapper can execute them.
