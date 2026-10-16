# Evaluator ownership

`core_eval.Session` coordinates evaluation and inference. Its values live in
`eval_values.Store`: stable handles, atomic parallel-table publication,
evidence, record shapes, borrowed views and owned snapshots share one cleanup
owner.

Private region backing, specialization caches and retained records have distinct
owners. Cache frames retire before backing regions. Live query/receipt hooks
stay with the session; snapshots retain no mutable solver or region authority.

Execution dispatch preserves one fuel charge per original node. Collection keeps
source observations before constraints and the original ordered child walk.
Responsibility routines retain the current diagnostic and exit context.

The focused split preserves structure sizes, exact ordinary Wasm/work/allocation
counts and imported fresh/edit/revert/failed-edit repair/restart output,
diagnostics and archive payload. Ten native laws, 25 guest laws and 422 selected
analyzer files pass. All native test interfaces compile; this is not a full
suite execution. `build/bench/finish-rest-20261015/evaluator-owners/` contains
exact before/source pins and measurements. Final common CPU qualification and
the compiler gate remain required; longer non-dispatch inference/scheduling
routines remain visible.
