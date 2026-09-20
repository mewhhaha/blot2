throw new Error(
  "The sandbox prototype is paused: its compiler-specific ECS/GUI backend was removed. " +
    "Generic effects/descriptors, scalar host callbacks, tuples, record construction/patterns, immutable arrays and file imports are implemented. " +
    "game.blot shows the source-library design; record field access, state resolvers, a composite capability/state ABI and the source-defined ECS remain pending. " +
    "See case-study/ecs/source-api.md and case-study/ecs/PLAN.md.",
);
