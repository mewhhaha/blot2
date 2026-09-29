import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeProjectCompiler } from "./native_project.ts";
import { loadSourceProject } from "./source_project.ts";

const executable = new URL("../generated/compiler/blotc", import.meta.url);
const entry = new URL("file:///virtual-schema-cache/main.blot");
const library = new URL("file:///virtual-schema-cache/schema.blot");
const schema = `type End is data = #End
type Entry { head, tail } is data = #Entry { head, tail }
const End.contains = fn (end: End) => fn witness => #False
const Entry.contains = fn entry => fn witness => do:
  let #Entry { head, tail } = entry
  if #Type head == #Type witness:
    return #True
  return tail.contains(witness)
const schema = #Entry { head: #True, tail: #Entry { head: 7, tail: #End } }
`;
const main = `import * as s from "./schema"
entry const answer_bool = s.schema.contains(#True)
entry const answer_u32 = s.schema.contains(7)
entry const answer_f32 = s.schema.contains(1.0)
entry const ask_bool = fn () => answer_bool
entry const ask_u32 = fn () => answer_u32
entry const ask_f32 = fn () => answer_f32
`;
const edit = (before: string, after: string) => {
  ok(schema.includes(before));
  return schema.replace(before, after);
};

async function answers(bytes: Uint8Array): Promise<number[]> {
  const instance = await WebAssembly.instantiate(
    await WebAssembly.compile(bytes.slice().buffer),
  );
  return ["ask_bool", "ask_u32", "ask_f32"].map((name) => {
    const fn = instance.exports[name];
    ok(typeof fn === "function", `${name} missing from Wasm exports`);
    return Number(fn(0));
  });
}

for (const threads of [1, 4]) {
  Deno.test(`schema project session preserves edits and rollback with ${threads} workers`, async () => {
    const files = new Map([[entry.href, main], [library.href, schema]]);
    const readSource = (url: URL) => {
      const source = files.get(url.href);
      if (source === undefined) {
        throw new Error(`missing fixture module ${url}`);
      }
      return Promise.resolve(source);
    };
    const session = await createNativeProjectCompiler({
      executable,
      threads,
      readSource,
    });
    const cold = await createNativeCompiler({ executable, threads });
    const clean = async () =>
      cold.compile(await loadSourceProject(entry, { readSource }));
    try {
      let first = true;
      const revisions: readonly [string, number[]][] = [
        [schema, [1, 1, 0]],
        [edit("return tail.contains(witness)", "return #False"), [1, 0, 0]],
        [
          edit(
            "const End.contains = fn (end: End) => fn witness => #False",
            "const End.contains = fn (end: End) => fn witness => #True",
          ),
          [1, 1, 1],
        ],
        [
          edit("type End is data = #End", "type End is data = #End | #Another"),
          [
            1,
            1,
            0,
          ],
        ],
        [schema, [1, 1, 0]],
      ];
      for (const [revision, expected] of revisions) {
        files.set(library.href, revision);
        const warm = await session.compile(entry);
        const fresh = await clean();
        if (first) {
          const staged = (artifact: typeof fresh) =>
            artifact.analysis.functions
              .filter((signature) => signature.name.startsWith("$schema["))
              .map((signature) => signature.name);
          ok(
            staged(fresh).length > 0,
            "cold schema capture did not produce helpers",
          );
          equal(staged(warm.artifact), staged(fresh));
          first = false;
        }
        equal(warm.artifact.bytes, fresh.bytes);
        equal(await answers(warm.artifact.bytes), expected);
        ok(!warm.stats.result_reused);
      }
      const same = await session.compile(entry);
      ok(same.stats.result_reused);
      equal(await answers(same.artifact.bytes), [1, 1, 0]);

      // A no-template project exercises the direct selection fast path.
      files.set(entry.href, "entry const answer = fn () => 7\n");
      equal(
        (await session.compile(entry)).artifact.bytes,
        (await clean()).bytes,
      );
      files.set(entry.href, main);
      equal(
        (await session.compile(entry)).artifact.bytes,
        (await clean()).bytes,
      );

      files.set(
        library.href,
        edit("return tail.contains(witness)", "return unknown_name"),
      );
      await rejects(() => session.compile(entry));
      files.set(library.href, schema);
      const recovered = await session.compile(entry);
      equal(recovered.artifact.bytes, (await clean()).bytes);
      equal(await answers(recovered.artifact.bytes), [1, 1, 0]);
    } finally {
      await session.dispose();
      await cold.dispose();
    }
  });
}
