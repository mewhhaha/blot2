export function arithmeticSource(
  shape: "balanced" | "uneven" | "clustered",
  changed: boolean,
): string {
  return Array.from({ length: 64 }, (_, index) => {
    const steps = shape === "balanced" ||
        (shape === "clustered" ? index < 8 : index % 8 === 0)
      ? 64
      : 8;
    return [
      `export fn entry_${index} value => do:`,
      ...Array.from(
        { length: steps },
        (_, step) =>
          `  let value_${step} = @u32.add ${
            step === 0 ? "value" : `value_${step - 1}`
          } ${changed && index === 0 && step === 0 ? 2 : 1}`,
      ),
      `  return value_${steps - 1}`,
    ].join("\n");
  }).join("\n");
}

export function readerSource(count: number, changed: boolean): string {
  return [
    "effect Reader.ask: Unit -> U32",
    "const reader = @effect.provider Reader.ask (fn () => 1)",
    ...Array.from({ length: count }, (_, index) =>
      `fn work_${index} () => do:
  use value <- Reader.ask ()
  return @u32.add value ${changed && index === 0 ? 2 : 1}
export fn entry_${index} () => do reader:
  use value <- work_${index} ()
  return value`),
  ].join("\n");
}

export function chainSource(changed: boolean): string {
  return [
    `fn work_0 value => @u32.add value ${changed ? 2 : 1}`,
    ...Array.from(
      { length: 63 },
      (_, index) =>
        `fn work_${index + 1} value => @u32.add (work_${index} value) 1`,
    ),
    "export fn entry_0 value => work_63 value",
  ].join("\n");
}

export const benchmarkWorkloads = [
  ...[8, 64].map((count) => ({
    name: `reader_${count}`,
    source: readerSource(count, false),
    changed: readerSource(count, true),
    expected: 2,
  })),
  ...(["balanced", "uneven", "clustered"] as const).map((shape) => ({
    name: `${shape}_64`,
    source: arithmeticSource(shape, false),
    changed: arithmeticSource(shape, true),
    expected: 64,
  })),
  {
    name: "chain_64",
    source: chainSource(false),
    changed: chainSource(true),
    expected: 64,
  },
];
