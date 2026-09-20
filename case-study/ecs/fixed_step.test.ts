import assert from "node:assert/strict";
import { createFixedStepClock, planFixedSteps } from "./fixed_step.ts";

const close = (actual: number, expected: number) =>
  assert.ok(Math.abs(actual - expected) < 1e-12, `${actual} != ${expected}`);

Deno.test("fixed clock starts without simulation and advances exact boundaries", () => {
  const empty = createFixedStepClock();
  const first = planFixedSteps(empty, 0);
  assert.equal(first.rebaseReason, "initial");
  assert.equal(first.steps, 0);
  assert.equal(first.alpha, 0);
  assert.equal(empty.timestampSeconds, null);
  const half = planFixedSteps(first.clock, 1 / 120);
  assert.equal(half.steps, 0);
  close(half.alpha, 0.5);
  const full = planFixedSteps(half.clock, 1 / 60);
  assert.equal(full.steps, 1);
  close(full.alpha, 0);
  assert.equal(full.droppedSeconds, 0);
  close(half.clock.remainderSeconds, 1 / 120);
  assert.ok(Object.isFrozen(full) && Object.isFrozen(full.clock));
});

Deno.test("fixed clock conserves fractional time and has no long-running tick drift", () => {
  let clock = planFixedSteps(createFixedStepClock(), 0).clock;
  let steps = 0;
  for (let frame = 1; frame <= 600; frame++) {
    const plan = planFixedSteps(clock, frame / 120);
    steps += plan.steps;
    assert.ok(plan.alpha >= 0 && plan.alpha < 1);
    assert.equal(plan.droppedSeconds, 0);
    clock = plan.clock;
  }
  assert.equal(steps, 300);
  close(clock.remainderSeconds, 0);
  const before = planFixedSteps(clock, 5 + 1 / 60 - 1e-8);
  assert.equal(before.steps, 0, "do not advance a genuinely incomplete tick");
});

Deno.test("fixed clock caps work, drops whole excess steps, and retains interpolation", () => {
  const initial = planFixedSteps(createFixedStepClock(), 0).clock;
  const capped = planFixedSteps(initial, 0.12);
  assert.equal(capped.steps, 5);
  close(capped.alpha, 0.2);
  close(capped.droppedSeconds, 2 / 60);
  close(
    capped.steps * capped.stepSeconds + capped.clock.remainderSeconds +
      capped.droppedSeconds,
    0.12,
  );
  const stalled = planFixedSteps(initial, 1);
  assert.equal(stalled.steps, 5);
  close(stalled.alpha, 0);
  close(stalled.droppedSeconds, 1 - 5 / 60);
  const after = planFixedSteps(stalled.clock, 1 + 1 / 60);
  assert.equal(
    after.steps,
    1,
    "the dropped backlog must not leak into later frames",
  );
  assert.equal(after.droppedSeconds, 0);
});

Deno.test("backward and requested rebases explicitly reset timing without simulation", () => {
  const initial = planFixedSteps(createFixedStepClock(), 10).clock;
  const half = planFixedSteps(initial, 10 + 1 / 120).clock;
  const backward = planFixedSteps(half, 9);
  assert.equal(backward.rebaseReason, "backward");
  assert.equal(backward.steps, 0);
  assert.equal(backward.alpha, 0);
  assert.equal(backward.droppedSeconds, 0);
  const reset = planFixedSteps(half, 1000, { rebase: true });
  assert.equal(reset.rebaseReason, "requested");
  assert.equal(reset.steps, 0);
  assert.equal(reset.clock.remainderSeconds, 0);
  assert.equal(planFixedSteps(backward.clock, 9 + 1 / 60).steps, 1);
  assert.equal(planFixedSteps(initial, 10).steps, 0);
  assert.equal(half.timestampSeconds, 10 + 1 / 120);
});

Deno.test("fixed clock validates timestamp and configuration boundaries", () => {
  for (const value of [NaN, Infinity, -Infinity, -1]) {
    assert.throws(
      () => planFixedSteps(createFixedStepClock(), value),
      /timestampSeconds/,
    );
  }
  for (const value of [0, -1, NaN, Infinity]) {
    assert.throws(
      () => createFixedStepClock({ stepSeconds: value }),
      /stepSeconds/,
    );
    assert.throws(
      () => createFixedStepClock({ maxElapsedSeconds: value }),
      /maxElapsedSeconds/,
    );
  }
  for (
    const value of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]
  ) {
    assert.throws(() => createFixedStepClock({ maxSteps: value }), /maxSteps/);
  }
  assert.throws(
    () => createFixedStepClock({ stepSeconds: Number.MIN_VALUE }),
    /numeric range/,
  );
  const configured = planFixedSteps(
    createFixedStepClock({
      stepSeconds: 0.1,
      maxElapsedSeconds: 1,
      maxSteps: 2,
    }),
    0,
  );
  const result = planFixedSteps(configured.clock, 0.45);
  assert.equal(result.steps, 2);
  close(result.alpha, 0.5);
  close(result.droppedSeconds, 0.2);
});
