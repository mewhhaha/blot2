import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import { formatDiagnostic } from "./source_frontend.ts";
import { ecsWorkload } from "./ecs_workload.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  NativeProtocolError,
} from "./native_protocol.ts";
import { createSourceFrontend } from "./source_frontend.ts";

function diagnostic(error: unknown) {
  if (!(error instanceof SourceError)) throw error;
  return {
    code: error.code,
    message: error.message,
    start: error.start,
    end: error.end,
    origin: error.origin,
  };
}

for (const prelude of ["none", "default"] as const) {
  Deno.test(`native source/compiler parity with ${prelude} prelude`, async () => {
    const js = await createSourceCompiler({ prelude });
    const native = await createNativeCompiler({ prelude });
    try {
      for (
        const name of ["scalar", "prelude", "ecs_runtime", "syntax", "ecs"]
      ) {
        const source = await Deno.readTextFile(
          new URL(`../examples/${name}.blot`, import.meta.url),
        );
        for (const operation of ["analyze", "compile", "compileEcs"] as const) {
          let expected;
          try {
            expected = js[operation](source);
          } catch (error) {
            const expectedError = diagnostic(error);
            await rejects(() => native[operation](source), (actual) => {
              equal(diagnostic(actual), expectedError, `${name}: ${operation}`);
              return true;
            });
            continue;
          }
          equal(
            await native[operation](source),
            expected,
            `${name}: ${operation}`,
          );
        }
      }
    } finally {
      js.dispose();
      await native.dispose();
    }
  });
}

Deno.test("native const values preserve closures, captures, and nested ADTs", async () => {
  const source = `
data Maybe a = Some a | Nothing
fn identity value => value
const empty = Nothing
const nested = Some (Some 42)
const reference = identity
const constructor = Some
const closure = (fn captured => fn value => @u32.add captured value) 2
export fn answer () => closure 40
`;
  const js = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    equal(await native.analyze(source), js.analyze(source));
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("native diagnostics retain source offsets, budgets, and recovery", async () => {
  const native = await createNativeCompiler({ prelude: "none" });
  const js = await createSourceCompiler({ prelude: "none" });
  try {
    const cases = [
      { source: "// 😀\r\nexport fn answer () => missing\r\n" },
      { source: "export fn answer () => @u32.add True 1\n" },
      { source: "const answer = 42\n", const_steps: 0n },
      { source: "export fn answer () => do:\n  return 42\n" },
    ];
    for (const entry of cases) {
      let expected;
      try {
        expected = js.compile(entry.source, entry);
      } catch (error) {
        const expectedError = diagnostic(error);
        await rejects(() => native.compile(entry.source, entry), (actual) => {
          equal(diagnostic(actual), expectedError);
          ok(
            formatDiagnostic("game.blot", entry.source, actual as SourceError)
              .startsWith("game.blot:"),
          );
          return true;
        });
        continue;
      }
      equal(await native.compile(entry.source, entry), expected);
    }
    await rejects(() => native.compile("", { const_steps: -1n }), RangeError);
    await rejects(
      () => native.compile("", { const_steps: 0x1000000000000n }),
      RangeError,
    );
  } finally {
    js.dispose();
    await native.dispose();
  }
});

for (const threads of [1, 4]) {
  Deno.test(`native ${threads}-thread ECS output executes and matches JS`, async () => {
    const native = await createNativeCompiler({ threads });
    const js = await createSourceCompiler();
    try {
      const source = ecsWorkload(16);
      const artifact = await native.compileEcs(source);
      equal(artifact, js.compileEcs(source));
      const runtime = await createEcsRuntime(artifact);
      const identity = (declaration: string) => ({
        $: "TypeId" as const,
        module_name: "main",
        declaration,
      });
      const initial = runtime.createWorld({
        entityCount: 1,
        components: Array.from({ length: 16 }, (_, index) => [
          { identity: identity(`Position${index}`), values: [2] },
          { identity: identity(`Velocity${index}`), values: [3] },
        ]).flat(),
        resources: [{ identity: identity("DeltaTime"), value: 2 }],
      });
      const next = runtime.run(initial);
      for (let index = 0; index < 16; index++) {
        equal(runtime.readComponent(next, identity(`Position${index}`), 0), 8);
        equal(
          runtime.readComponent(initial, identity(`Position${index}`), 0),
          2,
        );
      }
    } finally {
      await native.dispose();
      js.dispose();
    }
  });
}

Deno.test("native protocol rejects malformed responses and invalid request scalars", async () => {
  for (
    const payload of [new Uint8Array(), new Uint8Array(3), new Uint8Array(12)]
  ) {
    throws(() => decodeNativeResponse(payload), NativeProtocolError);
  }
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const source = frontend.prepare("");
    const request = {
      operation: "analyze" as const,
      root: source.root,
      prelude: source.prelude,
      fuel: source.nodeCount,
      const_steps: 10n,
    };
    throws(
      () => encodeNativeRequest({ ...request, fuel: -1n }),
      NativeProtocolError,
    );
    throws(
      () =>
        encodeNativeRequest({
          ...request,
          root: { ...request.root, text: "\ud800" },
        }),
      Error,
    );
  } finally {
    frontend.dispose();
  }
});
