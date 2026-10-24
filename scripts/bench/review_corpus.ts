// Held-out structural shapes for the CT106 performance screen. These are
// opt-in experiments, separate from the existing deterministic budget corpus.
import {
  diamond,
  type SyntheticProgram,
  type SyntheticProject,
} from "./corpus.ts";

function wideRecord(width: number): SyntheticProgram {
  const fields = Array.from(
    { length: width },
    (_, i) => `f${i}: @u32.add x ${i + 1}`,
  );
  return {
    name: "review_record",
    size: width,
    source: `const keep = fn value => value
entry const main = fn (x: U32) => do:
  let value = keep { ${fields.join(", ")} }
  break @u32.add value.f0 value.f${width - 1}
`,
    edit: { search: "f0: @u32.add x 1", replace: "f0: @u32.add x 2" },
  };
}
function wideEffects(width: number): SyntheticProgram {
  const effects = Array.from({ length: width }, (_, i) => `Read${i}`);
  return {
    name: "review_effects",
    size: width,
    source:
      effects.map((name) => `type ${name} is effect = Unit -> U32`).join("\n") +
      `\nconst run = fn (action: Unit -> U32 ! {${
        effects.join(", ")
      }}) => do:\n` +
      Array.from({ length: 16 }, (_, i) => `  use value${i} <- action ()\n`)
        .join("") +
      "  break @u32.add value0 1\n" +
      "const action = fn () => do:\n" +
      effects.map((name, i) => `  use result${i} <- ${name} ()\n`).join("") +
      "  break result0\nentry const main = fn (x: U32) => " +
      effects.map((name, i) =>
        `${
          i === 0 ? "" : "  ".repeat(i) + "break "
        }do (@effect.provider ${name} (fn () => x)):\n`
      ).join("") +
      "  ".repeat(width) + "break run action\n",
    edit: { search: "@u32.add value0 1", replace: "@u32.add value0 2" },
  };
}
function deepClosure(depth: number): SyntheticProgram {
  return {
    name: "review_closures",
    size: depth,
    source: `entry const main = fn (x: U32) => do:\n  let nested = ` +
      Array.from({ length: depth }, (_, i) => `fn (v${i}: U32) => `).join("") +
      `@u32.add v0 (@u32.add v${depth - 1} 1)\n  break nested ` +
      Array(depth).fill("x").join(" ") + "\n",
    edit: {
      search: `@u32.add v${depth - 1} 1`,
      replace: `@u32.add v${depth - 1} 2`,
    },
  };
}
function modules(count: number): SyntheticProject {
  const files: Record<string, string> = {
    "m0.blot": "const step = fn (x: U32) => @u32.add x 1\n",
  };
  for (let i = 1; i < count; i++) {
    files[`m${i}.blot`] = `import * as previous from "./m${
      i - 1
    }"\nconst step = fn (x: U32) => @u32.add (previous.step x) 1\n`;
  }
  files["main.blot"] = `import * as last from "./m${
    count - 1
  }"\nentry const main = fn (x: U32) => last.step x\n`;
  return {
    name: `review_modules_${count}`,
    files,
    entry: "main.blot",
    scenarios: [{
      name: "producer_body",
      replacements: [{
        file: "m0.blot",
        search: "@u32.add x 1",
        replace: "@u32.add x 2",
      }],
    }],
  };
}
export const reviewPrograms: readonly SyntheticProgram[] = [
  wideRecord(32),
  wideRecord(128),
  wideEffects(16),
  wideEffects(64),
  deepClosure(16),
  deepClosure(64),
  { ...diamond(10), name: "review_shared_dag" },
  {
    name: "review_small",
    size: 1,
    source: "entry const main = fn (x: U32) => @u32.add x 1\n",
    edit: { search: "@u32.add x 1", replace: "@u32.add x 2" },
  },
];
export const reviewProjects: readonly SyntheticProject[] = [modules(32)];
