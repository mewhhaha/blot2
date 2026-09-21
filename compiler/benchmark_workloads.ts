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

export function staggeredSource(changed: boolean): string {
  return Array.from(
    { length: 8 },
    (_, depth) =>
      Array.from({ length: 8 }, (_, chain) => {
        const steps = depth === chain ? 64 : 2;
        const declaration = depth === 7
          ? `export fn entry_${chain}`
          : `fn work_${chain}_${depth}`;
        const input = depth === 0
          ? "value"
          : `(work_${chain}_${depth - 1} value)`;
        return [
          `${declaration} value => do:`,
          ...Array.from({ length: steps }, (_, step) =>
            `  let value_${step} = @u32.add ${
              step === 0 ? input : `value_${step - 1}`
            } ${changed && chain === 0 && depth === 0 && step === 0 ? 2 : 1}`),
          `  return value_${steps - 1}`,
        ].join("\n");
      }).join("\n"),
  ).join("\n");
}

export function diamondSource(changed: boolean): string {
  return Array.from({ length: 8 }, (_, region) => {
    const declarations = [`fn seed_${region} value => value`];
    for (let depth = 0; depth < 8; depth++) {
      const input = depth === 0
        ? `seed_${region}`
        : `join_${region}_${depth - 1}`;
      for (const branch of ["left", "right"]) {
        const steps = depth === region ? 64 : 2;
        declarations.push([
          `fn ${branch}_${region}_${depth} value => do:`,
          `  let initial = ${input} value`,
          ...Array.from(
            { length: steps },
            (_, step) =>
              `  let value_${step} = @u32.add ${
                step ? `value_${step - 1}` : "initial"
              } ${
                changed && region === 0 && depth === 7 && branch === "left" &&
                  step === 0
                  ? 2
                  : 1
              }`,
          ),
          `  return value_${steps - 1}`,
        ].join("\n"));
      }
      declarations.push(
        `fn join_${region}_${depth} value => @u32.add (left_${region}_${depth} value) (right_${region}_${depth} value)`,
      );
    }
    declarations.push(
      `export fn entry_${region} value => join_${region}_7 value`,
    );
    return declarations.join("\n");
  }).join("\n");
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
  {
    name: "diamonds_8",
    source: diamondSource(false),
    changed: diamondSource(true),
    expected: 16892,
  },
  {
    name: "staggered_64",
    source: staggeredSource(false),
    changed: staggeredSource(true),
    expected: 78,
  },
];
