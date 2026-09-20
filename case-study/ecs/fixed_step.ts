export interface FixedStepOptions {
  readonly stepSeconds?: number;
  readonly maxElapsedSeconds?: number;
  readonly maxSteps?: number;
}

export interface FixedStepClock {
  readonly timestampSeconds: number | null;
  readonly remainderSeconds: number;
  readonly stepSeconds: number;
  readonly maxElapsedSeconds: number;
  readonly maxSteps: number;
}

export interface FixedStepPlan {
  readonly clock: FixedStepClock;
  readonly steps: number;
  readonly stepSeconds: number;
  readonly alpha: number;
  /** Positive elapsed time discarded by the elapsed clamp or step cap. */
  readonly droppedSeconds: number;
  /** A rebase discards interpolation history and never simulates a step. */
  readonly rebaseReason: "initial" | "requested" | "backward" | null;
}

export function createFixedStepClock(
  options: FixedStepOptions = {},
): FixedStepClock {
  const stepSeconds = options.stepSeconds ?? 1 / 60;
  const maxElapsedSeconds = options.maxElapsedSeconds ?? 0.25;
  const maxSteps = options.maxSteps ?? 5;
  if (!Number.isFinite(stepSeconds) || stepSeconds <= 0) {
    throw new RangeError("fixed stepSeconds must be finite and positive");
  }
  if (!Number.isFinite(maxElapsedSeconds) || maxElapsedSeconds <= 0) {
    throw new RangeError("fixed maxElapsedSeconds must be finite and positive");
  }
  if (!Number.isSafeInteger(maxSteps) || maxSteps < 1) {
    throw new RangeError("fixed maxSteps must be a positive safe integer");
  }
  if (
    !Number.isFinite(maxElapsedSeconds + stepSeconds) ||
    maxElapsedSeconds / stepSeconds + 1 > Number.MAX_SAFE_INTEGER
  ) throw new RangeError("fixed clock limits exceed its numeric range");
  return Object.freeze({
    timestampSeconds: null,
    remainderSeconds: 0,
    stepSeconds,
    maxElapsedSeconds,
    maxSteps,
  });
}

export function planFixedSteps(
  clock: FixedStepClock,
  timestampSeconds: number,
  options: { readonly rebase?: boolean } = {},
): FixedStepPlan {
  if (!Number.isFinite(timestampSeconds) || timestampSeconds < 0) {
    throw new RangeError(
      "frame timestampSeconds must be finite and nonnegative",
    );
  }
  const rebaseReason = options.rebase
    ? "requested"
    : clock.timestampSeconds === null
    ? "initial"
    : timestampSeconds < clock.timestampSeconds
    ? "backward"
    : null;
  if (rebaseReason !== null) {
    return Object.freeze({
      clock: Object.freeze({ ...clock, timestampSeconds, remainderSeconds: 0 }),
      steps: 0,
      stepSeconds: clock.stepSeconds,
      alpha: 0,
      droppedSeconds: 0,
      rebaseReason,
    });
  }
  const elapsedSeconds = timestampSeconds - clock.timestampSeconds!;
  const acceptedSeconds = Math.min(elapsedSeconds, clock.maxElapsedSeconds);
  const availableSeconds = clock.remainderSeconds + acceptedSeconds;
  const ticks = availableSeconds / clock.stepSeconds;
  // Absolute timestamps also lose precision in subtraction. Never round ahead
  // by more than a ten-millionth of a tick, even for enormous timestamps.
  const tolerance = Math.min(
    1e-7,
    8 * Number.EPSILON *
      Math.max(1, ticks, timestampSeconds / clock.stepSeconds),
  );
  const wholeSteps = Math.floor(ticks + tolerance);
  const steps = Math.min(wholeSteps, clock.maxSteps);
  const remainderSeconds = Math.max(
    0,
    availableSeconds - wholeSteps * clock.stepSeconds,
  );
  const droppedSeconds = elapsedSeconds - acceptedSeconds +
    (wholeSteps - steps) * clock.stepSeconds;
  if (!Number.isFinite(droppedSeconds)) {
    throw new RangeError("elapsed interval exceeds the finite clock range");
  }
  return Object.freeze({
    clock: Object.freeze({ ...clock, timestampSeconds, remainderSeconds }),
    steps,
    stepSeconds: clock.stepSeconds,
    alpha: remainderSeconds / clock.stepSeconds,
    droppedSeconds,
    rebaseReason: null,
  });
}
