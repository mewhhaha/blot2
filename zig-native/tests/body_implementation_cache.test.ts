import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
function spine(value: string) {
  for (let index = 0; index < 16; index++) value = `@u32.add (${value}) 0`;
  return value;
}
const implementation = (amount: number) =>
  `impl ScalarSource : Source U32 = {
  type Item = U32,
  const first = fn value => @u32.add value ${amount},
}
`;
const ordinarySource = (
  method = 1,
  caller = 0,
  head = implementation(method),
) => `
type Source s is contract = { type Item, const first: s -> (Source.Item s) }
${head}
const unrelated = fn (value: U32) => @u32.add (${spine("value")}) 7
const selected = fn (value: U32) => @u32.add (${
  spine("Source.first value")
}) ${caller}
entry const run = fn (value: U32) => @u32.add (${
  spine("unrelated value")
}) (selected value)
`;
for (
  const [codegenTier, annotation] of [
    ["optimized", "ordinary"],
    ["development", "ordinary"],
    ["optimized", "alias"],
    ["development", "alias"],
    ["optimized", "associated"],
    ["development", "associated"],
  ] as const
) {
  Deno.test(`mixed implementation modules reuse ${annotation} bodies through edits failures and revert (${codegenTier})`, async () => {
    const source = (
      method = 1,
      caller = 0,
      head = implementation(method),
    ) => {
      let text = ordinarySource(method, caller, head);
      if (annotation === "alias") {
        text = "type Scalar = U32\n" + text.replace(
          "const unrelated = fn (value: U32)",
          "const unrelated = fn (value: Scalar)",
        );
      }
      if (annotation === "associated") {
        text =
          "type Number is data = #Number U32\nconst Number.twice = fn (#Number value) => fn (delta: U32) => @u32.add value delta\n" +
          text.replace(
            `@u32.add (${spine("value")}) 7`,
            `@type.call "twice" (#Number (${spine("value")})) 7`,
          );
      }
      return text;
    };
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false as const,
    };
    const retained = await createZigProjectCompiler(options);
    try {
      const records: unknown[] = [];
      const badHead = `impl ScalarSource : Source F32 = {
  type Item = F32,
  const first = fn value => @f32.add value 1.0,
}`;
      const changedItem = `impl ScalarSource : Source U32 = {
  type Item = F32,
  const first = fn value => @u32.to_f32 value,
}`;
      const conditional = (witness: string) =>
        `type Ready a is contract = { type Proof }
${witness}
impl ScalarSource : Source U32 where { Ready U32 } = {
  type Item = U32,
  const first = fn value => @u32.add value 4,
}`;
      const ready = "impl ReadyScalar : Ready U32 = { type Proof = U32 }";
      const revisions: (readonly [string, number | null])[] = [
        [source(), 88],
        [source(4), 91],
        [source(4, 3), 94],
        [source(4, 3, badHead), null],
        [source(4, 3), 94],
        [source(4, 3, ""), null],
        [source(), 88],
        [source(4, 3, changedItem), null],
        [source(4, 3), 94],
        [
          source(
            4,
            3,
            implementation(4) +
              implementation(4).replace("ScalarSource", "Overlap"),
          ),
          null,
        ],
        [source(4, 3, conditional(ready)), 94],
        [source(4, 3, conditional("")), null],
        [source(4, 3, conditional(ready)), 94],
        [source(), 88],
      ];
      if (annotation === "alias") {
        revisions.push(
          [
            source(4, 3).replace(
              "type Scalar = U32",
              "private type Scalar = U32",
            ),
            94,
          ],
          [
            source(4, 3).replace("type Scalar = U32", "type Scalar = F32"),
            null,
          ],
          [source(4, 3), 94],
          [source(), 88],
          [
            source(4, 3).replace(
              "type Scalar = U32",
              "type Scalar = Source.Item U32",
            ),
            94,
          ],
          [
            source(5, 3).replace(
              "type Scalar = U32",
              "type Scalar = Source.Item U32",
            ),
            95,
          ],
          [
            source(5, 3, badHead).replace(
              "type Scalar = U32",
              "type Scalar = Source.Item U32",
            ),
            null,
          ],
          [source(5, 3), 95],
          [source(), 88],
        );
      }
      if (annotation === "associated") {
        revisions.push(
          [
            source().replace("@u32.add value delta", "@u32.sub value delta"),
            74,
          ],
          [source().replace("(delta: U32)", "(delta: F32)"), null],
          [source(), 88],
          [source().replace(/^const Number.twice[^\n]*\n/m, ""), null],
          [source(), 88],
          [
            source() +
            "\ntype Float is data = #Float F32\nconst Float.twice = fn (#Float value) => fn (delta: F32) => @f32.add value delta\n",
            88,
          ],
          [source(), 88],
        );
      }
      for (let revision = 0; revision < revisions.length; revision++) {
        const [text, answer] = revisions[revision];
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = { [entry]: text };
          const expected = await fresh.build({ sources });
          const actual = await retained.build({ sources });
          assert.equal(actual.success, expected.success);
          if (!actual.success || !expected.success) {
            assert(!actual.success && !expected.success);
            assert.equal(
              answer,
              null,
              JSON.stringify({ revision, diagnostics: actual.diagnostics }),
            );
            assert.deepEqual(actual.diagnostics, expected.diagnostics);
            continue;
          }
          assert.notEqual(answer, null);
          assert.deepEqual(actual.bytes, expected.bytes);
          assert.equal(
            actual.stats.nativeWorkSteps,
            expected.stats.nativeWorkSteps,
          );
          const elaborations = Number(
            actual.stats.frontend.body_elaborations,
          );
          const ordinary = Number(expected.stats.frontend.body_elaborations);
          records.push({
            revision,
            elaborations,
            ordinary,
            savedElaborations: ordinary - elaborations,
            cachedModules: actual.stats.cachedModules,
          });
          let expectedOrdinary = 4;
          let expectedReused = 2;
          if (annotation === "associated") {
            expectedOrdinary = 5;
            expectedReused = 3;
            if (revision === 19) expectedOrdinary++;
          }
          assert.equal(ordinary, expectedOrdinary);
          if (
            revision === 1 || revision === 2 || revision === 6 ||
            revision === 8 || revision === 13
          ) {
            if (revision === 1) expectedReused--;
            assert.equal(elaborations, expectedReused, JSON.stringify(records));
          }
          if (annotation === "associated") {
            if (revision === 14 || revision === 16) {
              assert.equal(elaborations, 2);
            }
            if (revision === 19) assert.equal(elaborations, 4);
            if (revision === 20) assert.equal(elaborations, 3);
          }
          if (annotation === "alias" && revision === 14) {
            // The declaration source is exact, but alias privacy is part of
            // its owned annotation recipe and must force a fresh elaboration.
            assert.equal(elaborations, 3);
          }
          if (
            annotation === "alias" && (revision === 18 || revision === 19)
          ) {
            // Changing the annotation recipe rechecks its reader. A later
            // method-body edit preserves both semantic callers.
            let expected = 3;
            if (revision === 19) expected = 1;
            assert.equal(elaborations, expected, JSON.stringify(records));
          }
          if (
            annotation === "alias" &&
            (revision === 16 || revision === 21)
          ) {
            // Restoring privacy or replacing the projection recipe revokes
            // the annotation reader while the selected caller still reuses.
            assert.equal(elaborations, 2);
          }
          if (
            annotation === "alias" && (revision === 17 || revision === 22)
          ) {
            assert.equal(elaborations, 2);
          }
          const guest = await instantiateGuest(actual.bytes);
          try {
            assert.equal(guest.call("run", 40), answer);
          } finally {
            guest.dispose();
          }
        } finally {
          await fresh.dispose();
        }
      }
      console.log(JSON.stringify({ codegenTier, annotation, records }));
    } finally {
      await retained.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

for (const codegenTier of ["optimized", "development"] as const) {
  for (const local of [false, true]) {
    Deno.test(`generic selected body receipts preserve independent scalar uses (local=${local}, ${codegenTier})`, async () => {
      let selected = "Source.first value";
      for (let index = 0; index < 16; index++) {
        selected = `@product.get ((${selected}), ()) 0`;
      }
      if (local) {
        selected =
          `do:\n  let forward = fn item => Source.first item\n  return ${
            selected.replace("Source.first value", "forward value")
          }`;
      }
      const source = (amount: number, sibling: string, prefix = "") =>
        `${prefix}
type Source s is contract = { type Item, const first: s -> (Source.Item s) }
${implementation(amount)}
impl FloatSource : Source F32 = {
  type Item = F32,
  const first = fn value => @f32.add value 0.5,
}
const selected = fn value => ${selected}
entry const run = fn (value: U32) => selected value
entry const fraction = fn (value: F32) => selected value
entry const captures = fn (value: U32) => do:
  let forward = fn item => (Source.first value, Source.first item)
  let whole = forward 1
  let fraction = forward 0.5
  return @u32.add (@product.get whole 0) (@product.get fraction 0)
entry const sibling = ${sibling}
`;
      const directory = await Deno.makeTempDir();
      const entry = `${directory}/main.blot`;
      const options = {
        executable,
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          source(1, "1"),
          source(4, "1"),
          source(4, "2", "const earlier_spelling = 3"),
          source(4, "missing"),
          source(4, "3"),
          source(4, "4").replace(
            "impl FloatSource : Source F32",
            "impl FloatSource : Source Bool",
          ),
          source(1, "5"),
        ];
        for (const [revision, text] of revisions.entries()) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert(!actual.success && !expected.success);
              assert(
                revision === 3 || revision === 5,
                JSON.stringify(actual.diagnostics),
              );
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            if (revision !== 0) {
              assert(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              let amount = 4;
              if (revision === 0 || revision === 6) amount = 1;
              assert.equal(guest.call("run", 40), 40 + amount);
              assert.equal(guest.call("fraction", 40.5), 41);
              assert.equal(guest.call("captures", 40), 2 * (40 + amount));
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }

  Deno.test(`selected body receipts relocate imported contracts and member spellings (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/source.blot`;
    const extra = `${directory}/extra.blot`;
    const archive = `${directory}/source.blotdep`;
    const producer =
      `type Source s is contract = { type Item, const first: s -> (Source.Item s) }\n${
        implementation(1)
      }`;
    const source = (sibling: string, prefix = "") =>
      `${prefix}
import { Source, ScalarSource } from "./source"
const selected = fn (value: U32) => ${spine("Source.first value")}
entry const run = fn (value: U32) => selected value
entry const sibling = ${sibling}
`;
    try {
      await Deno.writeTextFile(entry, source("1"));
      await Deno.writeTextFile(dependency, producer);
      await Deno.writeTextFile(extra, "const earlier_spelling = 3\n");
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false as const,
        };
        const retained = await createZigProjectCompiler(options);
        try {
          const edits: [string, string, number | null][] = [
            [source("1"), producer, 41],
            [source("2"), producer, 41],
            [source("3", 'import * as earlier from "./extra"'), producer, 41],
            [source("missing"), producer, null],
            [source("4"), producer, 41],
            [
              source("5").replace("Source.first", "Source.absent"),
              producer,
              null,
            ],
            [source("6"), producer, 41],
          ];
          if (dependencies === undefined) {
            edits.push(
              [
                source("7"),
                producer.replace("@u32.add value 1", "@u32.add value 4"),
                44,
              ],
              [source("8"), producer.replace("Source U32", "Source F32"), null],
              [source("9"), producer, 41],
            );
          }
          for (
            const [revision, [text, dependencySource, answer]] of edits
              .entries()
          ) {
            const fresh = await createZigProjectCompiler(options);
            try {
              const sources = { [entry]: text };
              if (dependencies === undefined) {
                sources[dependency] = dependencySource;
              }
              const expected = await fresh.build({ sources });
              const actual = await retained.build({ sources });
              assert.equal(actual.success, expected.success);
              if (!actual.success || !expected.success) {
                assert(!actual.success && !expected.success);
                assert.equal(answer, null);
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                continue;
              }
              assert.notEqual(answer, null);
              assert.deepEqual(actual.bytes, expected.bytes);
              assert.equal(
                actual.stats.nativeWorkSteps,
                expected.stats.nativeWorkSteps,
              );
              if (revision !== 0 && revision < 7) {
                assert.equal(
                  Number(actual.stats.frontend.body_elaborations),
                  2,
                  JSON.stringify({
                    revision,
                    dependencies,
                    frontend: actual.stats.frontend,
                  }),
                );
              }
              const guest = await instantiateGuest(actual.bytes);
              try {
                assert.equal(guest.call("run", 40), answer);
              } finally {
                guest.dispose();
              }
            } finally {
              await fresh.dispose();
            }
          }
        } finally {
          await retained.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
