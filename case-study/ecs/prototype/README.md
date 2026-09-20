# Retired compiler-coupled prototype

These files preserve the previous experiments and measurements for reference.
They are not runnable with the current compiler: `compileEcs`, `compileApp`,
compiler-generated storage/query/scheduling, and game/GUI intrinsics have been
removed. Relative imports describe their original locations and are not a
supported module graph.

The next sandbox must use a Blot-source ECS and source-declared host effects,
with explicit IO capabilities passed to the entrypoint. Do not restore the old
compiler hooks to make these experiments run. See [the current plan](../PLAN.md)
and [the capability contract](../../../compiler/effects-and-io.md).
