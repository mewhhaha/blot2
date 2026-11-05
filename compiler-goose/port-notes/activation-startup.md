# Activation and startup writing record

Full production first writing passes are present for activation_graph,
activation_intersection, activation_model, startup_graph,
startup_occurrence_flow, startup_occurrence_plan, and startup_runtime_reach.
Native test helpers remain oracle evidence. No build, test, formatter, compiler,
or static verification ran.

StartupGraph copies declaration identities and reference/candidate edges,
preserves function-before-constant source order, normalizes external aliases,
and reproduces compact Kosaraju finish/component/member ordering. Strong cell
cycles reject before weak occurrence edges influence ordering. Runtime retention
walks source bodies for named/runtime declarations and immutable completed value
captures for constants, including used partial parameters and every actual
capture graph. It never evaluates a binding.

The occurrence interpreter retains complete provenance, producer replay against
completed values, named/anonymous/primitive/constructor application, selected
scalar dispatch, pattern and control alternatives, partial return joins,
canonical payload/field projection, aggregate retention, and current occurrence
facts. Native limits are 100000 steps, depth128, 32768 values, and 131072 child
or field words. A private sticky Error unwinds internal fixed-descriptor helpers;
no result is published after a failure.

ActivationGraph preserves all native heap/control/provider/call checks,
32 interpretation rounds, 262144 work, 64 sites/contexts/code targets,
256 stores/calls/paths, 16 active calls, 128 locals/stack values, 64 control
frames, 4096 instructions, and 16 object words. Flow stores copied fixed cell
values plus the exact written mask. This reproduces immutable arena snapshots:
subsequent State writes cannot mutate a branch or an outcome's earlier cells.
Every temporary outcome and pending-state run is explicitly released.

Intersection independently derives both complete reports, then checks exact
request targets, invocation/creation/event correspondence, declaration-to-use
type and symbolic row mappings, runtime operation keys, allocation receipts,
nominal/closure layouts, installation identity, and every grouped store edge.
Its mutable evidence copy preserves immutable report IDs and rebuilds only
derived hash chains from the canonical fingerprints; the original report stays
immutable. Only OutOfMemory escapes analyze; unsupported correspondence declines.

ActivationModel owns temporary function/span/operation arrays while borrowing
pinned graph/evidence/key storage for one synchronous query. withBorrowed invokes
its callback while that view is live, then releases those arrays. No mutable
inference owner is retained in the candidate proof.
