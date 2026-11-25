import { compileAndRun, equal } from "./compile_helpers.ts";
type Program = {
  name: string;
  source: string;
  expected: number;
  constantCall?: string;
  calls?: readonly (readonly [number, number])[];
};

// Reproduce source positions that previously made an inner do label equal a
// generated loop label. The frontend reserves offset zero for an empty prelude.
function collidingDo(
  prefix: string,
  slot: number,
  suffix: string,
  indentation = "    ",
): string {
  const oldLoopLabel = (prefix.indexOf("for ") + 1) * 16 + slot;
  const beforeDo = indentation + "//";
  const afterComment = "\n" + indentation + "let local = ";
  const padding = oldLoopLabel - 1 - prefix.length - beforeDo.length -
    afterComment.length;
  return prefix + beforeDo + "x".repeat(padding) + afterComment + "do:\n" +
    suffix;
}

const programs: readonly Program[] = [
  {
    name:
      "nested do cannot intercept an ordinary loop break at colliding offsets",
    source: collidingDo(
      "#entry const answer = func () => return do:\n  for index in 0 .. 1:\n",
      14,
      '      break\n    @panic "inner do intercepted the loop break"\n  break 42\n',
    ),
    expected: 42,
  },
];

for (const program of programs) {
  Deno.test(`do runtime: ${program.name}`, async () => {
    const source = program.source +
      `\n#entry const expected = ${program.constantCall ?? "answer ()"}\n`;
    await compileAndRun(source, (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      for (
        const [argument, expected] of program.calls ??
          [[0, program.expected], [0, program.expected]]
      ) {
        equal(
          guest.call("answer", abi?.parameter === "Unit" ? null : argument),
          expected,
        );
      }
      equal(guest.read("expected"), program.expected);
    });
  });
}
