import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

function inMemory(modules: Record<string, string>) {
  return {
    readSource(url: URL) {
      const source = modules[url.pathname.slice(1)];
      return source === undefined
        ? Promise.reject(new Deno.errors.NotFound(url.href))
        : Promise.resolve(source);
    },
  };
}

Deno.test("expression tags stack nearest first and annotate the final const or let value", async () => {
  const source = await Deno.readTextFile(
    new URL("../examples/tags.blot", import.meta.url),
  );
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as WebAssembly.Global).value, 41);
    equal((instance.exports.truth as WebAssembly.Global).value, 1);
    equal((instance.exports.initialized as WebAssembly.Global).value, 42);
    equal((instance.exports.next as (value: number) => number)(41), 42);
    equal((instance.exports.reduced as WebAssembly.Global).value, 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("tags resolve local aliases, named imports, and qualified imports", async () => {
  const library =
    "const inc = fn value => value + 1\nconst add = fn amount => fn value => value + amount\n";
  const source = `
import { inc as imported } from "./lib"
import * as lib from "./lib"
const alias = imported
#[alias] entry const local: U32 = 41
#[imported] entry const named: U32 = 41
#[lib.add 1] entry const qualified: U32 = 41
`;
  const project = await loadSourceProject(
    new URL("file:///main.blot"),
    inMemory({ "main.blot": source, "lib.blot": library }),
  );
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(project);
    equal(await native.compile(project), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    for (const name of ["local", "named", "qualified"]) {
      equal((instance.exports[name] as WebAssembly.Global).value, 42);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("tag diagnostics point at the tag and unused tagged consts do not evaluate", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const unused =
      `#[fn value => @panic "unused"]\nconst unused: U32 = 1\nentry const answer = 42\n`;
    const artifact = reference.compile(unused);
    equal(await native.compile(unused), artifact);
    for (
      const [source, code] of [
        ["#[1] entry const answer = 42\n", "type_mismatch"],
        [
          "#[fn value => @u32.add True 1] entry const answer = 42\n",
          "type_mismatch",
        ],
        [
          "#[fn value => True + False] entry const answer = 42\n",
          "missing_associated",
        ],
        [
          '#[fn value => @panic "tag"] entry const answer: U32 = 42\n',
          "const_panic",
        ],
        ["#[fn value => value] entry const answer = answer\n", "recursive_tag"],
        ["#[fn value => value] data Box = Box U32\n", "unsupported_attribute"],
      ] as const
    ) {
      let expected: SourceError | undefined;
      throws(() => reference.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal([error.code, error.start], [code, source.indexOf("#[")]);
        expected = error;
        return true;
      });
      await rejects(() => native.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal([error.code, error.start], [expected?.code, expected?.start]);
        return true;
      });
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("deferred pattern diagnostics distinguish tags from their original values", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  const cases = [
    {
      source: `#[fn value => case value of
  True => 1
] entry const answer = True
`,
      code: "non_exhaustive_match",
      subject: "#[",
    },
    {
      source: `const expected = (1, 2)
#[fn value => case value of
  ^expected => 1
  _ => 0
] entry const answer = expected
`,
      code: "value_pattern_type",
      subject: "#[",
    },
    {
      source: `#[fn value => value] entry const answer = case True of
  True => 1
`,
      code: "non_exhaustive_match",
      subject: "case True of",
    },
    {
      source: `const expected = (1, 2)
#[fn value => value] entry const answer = case expected of
  ^expected => 1
  _ => 0
`,
      code: "value_pattern_type",
      subject: "case expected of",
    },
  ] as const;
  try {
    for (const { source, code, subject } of cases) {
      const expected = source.indexOf(subject);
      throws(() => reference.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal([error.code, error.start], [code, expected]);
        return true;
      });
      await rejects(() => native.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal([error.code, error.start], [code, expected]);
        return true;
      });
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("incremental edits to tag functions and arguments agree with clean JS and native builds", async () => {
  const revision = (step: number, extra: number) =>
    `const decorate = fn amount => fn value => value + amount + ${step}\n#[decorate ${extra}] entry const answer = 40\n`;
  const reference = await createSourceCompiler();
  const javascript = await createIncrementalCompiler();
  const native = await createNativeIncrementalCompiler();
  try {
    for (const [step, extra] of [[1, 1], [2, 1], [2, 2], [1, 1]]) {
      const source = revision(step, extra);
      const clean = reference.compile(source);
      equal((await javascript.compile(source)).artifact, clean);
      equal((await native.compile(source)).artifact, clean);
      const { instance } = await WebAssembly.instantiate(clean.bytes);
      equal(
        (instance.exports.answer as WebAssembly.Global).value,
        40 + step + extra,
      );
    }
  } finally {
    reference.dispose();
    await javascript.dispose();
    await native.dispose();
  }
});
