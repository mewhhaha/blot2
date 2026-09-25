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
import {
  decodeNativeResponse,
  encodeNativeRequest,
  NativeProtocolError,
} from "./native_protocol.ts";
import { createSourceFrontend } from "./source_frontend.ts";
import { instantiateGuest } from "./guest.ts";

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
        const name of ["scalar", "prelude", "generic_effects"]
      ) {
        const source = await Deno.readTextFile(
          new URL(`../examples/${name}.blot`, import.meta.url),
        );
        for (const operation of ["analyze", "compile"] as const) {
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
const identity = fn value => value
const empty = Nothing
const nested = Some (Some 42)
const reference = identity
const constructor = Some
const closure = (fn captured => fn value => @u32.add captured value) 2
const answer = fn () => closure 40
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
      { source: "// 😀\r\nconst answer = fn () => missing\r\n" },
      { source: "const answer = fn () => @u32.add True 1\n" },
      { source: "const answer = 42\n", const_steps: 0n },
      { source: "const answer = fn () => do:\n  return 42\n" },
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
  Deno.test(`native ${threads}-thread generic effects execute and match JS`, async () => {
    const native = await createNativeCompiler({ threads });
    const js = await createSourceCompiler();
    try {
      const source = await Deno.readTextFile(
        new URL("../examples/generic_effects.blot", import.meta.url),
      );
      const artifact = await native.compile(source);
      equal(artifact, js.compile(source));
      const module = new WebAssembly.Module(artifact.bytes);
      equal(WebAssembly.Module.imports(module), []);
      const instance = new WebAssembly.Instance(module);
      const answer = instance.exports.answer;
      const deferred = instance.exports.deferred;
      ok(typeof answer === "function");
      ok(typeof deferred === "function");
      equal(answer(0), 42);
      equal(deferred(0), 7);
    } finally {
      await native.dispose();
      js.dispose();
    }
  });
}

for (const threads of [1, 4]) {
  Deno.test(`native ${threads}-thread Wasm-only compiles return the full compile's bytes`, async () => {
    const native = await createNativeCompiler({ threads });
    const js = await createSourceCompiler();
    try {
      for (const name of ["scalar", "prelude", "generic_effects", "arrays"]) {
        const source = await Deno.readTextFile(
          new URL(`../examples/${name}.blot`, import.meta.url),
        );
        let full;
        try {
          full = await native.compile(source);
        } catch (error) {
          const expected = diagnostic(error);
          await rejects(
            () => native.compile(source, { analysis: false }),
            (actual) => {
              equal(diagnostic(actual), expected, name);
              return true;
            },
          );
          continue;
        }
        const wasm = await native.compile(source, { analysis: false });
        equal(wasm, { bytes: full.bytes }, name);
        ok(!("analysis" in wasm), name);
        equal(js.compile(source, { analysis: false }), wasm, name);
        // Guests need only the bytes: the ABI travels in blot:abi.
        const guest = await instantiateGuest(wasm.bytes);
        try {
          ok(guest.abi.functions.length + guest.abi.constants.length > 0);
        } finally {
          guest.dispose();
        }
      }
      const invalid = "const answer = fn () => @u32.add True 1\n";
      const expected = await native.compile(invalid).then(
        () => undefined,
        diagnostic,
      );
      ok(expected);
      await rejects(
        () => native.compile(invalid, { analysis: false }),
        (actual) => {
          equal(diagnostic(actual), expected);
          return true;
        },
      );
      for (const analysis of [0, "false", null]) {
        await rejects(
          () =>
            native.compile("", { analysis: analysis as unknown as boolean }),
          TypeError,
        );
        throws(
          () => js.compile("", { analysis: analysis as unknown as boolean }),
          TypeError,
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
