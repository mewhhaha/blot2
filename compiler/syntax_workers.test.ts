import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { arithmeticSource } from "./benchmark_workloads.ts";
import { createSourceFrontend, declarationOffsets } from "./source_frontend.ts";
import { CompilerError } from "./diagnostics.ts";
import { SourceError } from "./syntax.ts";
import { encodeNativeRequest } from "./native_protocol.ts";
import type { SyntaxJob, SyntaxReply } from "./syntax_workers.ts";

function reference(
  frontend: Awaited<ReturnType<typeof createSourceFrontend>>,
  source: string,
) {
  const parsed = frontend.prepare(source);
  return encodeNativeRequest({
    ...parsed,
    fuel: parsed.nodeCount,
    operation: "compile",
    const_steps: 10000n,
  });
}

const large = arithmeticSource("balanced", false);
const diagnostic = (error: unknown) => {
  ok(error instanceof SourceError);
  return {
    code: error.code,
    message: error.message,
    start: error.start,
    end: error.end,
    origin: error.origin,
  };
};

Deno.test("unexpected syntax worker failures reach the parent instead of hanging", async () => {
  const worker = new Worker(new URL("./syntax_worker.ts", import.meta.url), {
    type: "module",
  });
  const failed = Promise.withResolvers<string>();
  const timeout = setTimeout(
    () => failed.reject(new Error("Worker failure was not delivered")),
    10000,
  );
  worker.onerror = (event) => {
    event.preventDefault();
    failed.resolve(event.message);
  };
  worker.onmessage = ({ data: reply }: MessageEvent<SyntaxReply>) => {
    if (reply.kind !== "ready") {
      failed.reject(new Error("Invalid source unexpectedly encoded"));
    }
  };
  try {
    worker.postMessage(
      {
        source: null as unknown as string,
        sourceBase: 0,
      } satisfies SyntaxJob,
    );
    ok((await failed.promise).includes("Cannot read properties of null"));
  } finally {
    clearTimeout(timeout);
    worker.terminate();
  }
});

Deno.test("compact parallel frontend preserves exact request bytes, offsets, fuel, prelude and concurrent call ownership", async () => {
  for (const threads of [1, 2, 4, 8]) {
    const frontend = await createSourceFrontend({ threads });
    try {
      for (
        const source of [
          "",
          "const tiny = fn () => 42",
          `// Unicode 🙂\n${large}`,
          large.replaceAll("\n", "\r\n"),
          `import { external } from "./module"\n${large}`,
          `data Pair = #Pair { first: U32, second: U32 }\n${large}\nconst pair = #Pair { first: 0xFFFF_FFFF, second: 2147483648 }`,
        ]
      ) {
        const expected = reference(frontend, source);
        const actual = await frontend.prepareNative(source);
        equal(actual.encode("compile", 10000n), expected);
      }
      const sources = [
        large,
        large.replace(
          "value_0 = @u32.add value 1",
          "value_0 = @u32.add value 2",
        ),
      ];
      const actual = await Promise.all(
        sources.map((source) => frontend.prepareNative(source)),
      );
      actual.forEach((parsed, index) =>
        equal(
          parsed.encode("compile", 10000n),
          reference(frontend, sources[index]),
        )
      );
    } finally {
      frontend.dispose();
    }
  }
});

Deno.test("compact encoding and declaration diagnostics match the object frontend across examples", async () => {
  const frontend = await createSourceFrontend({ threads: 8 });
  try {
    for await (
      const entry of Deno.readDir(new URL("../examples/", import.meta.url))
    ) {
      if (!entry.name.endsWith(".blot")) continue;
      const source = await Deno.readTextFile(
        new URL(`../examples/${entry.name}`, import.meta.url),
      );
      const classic = frontend.prepare(source);
      const compact = await frontend.prepareNative(source);
      for (const operation of ["analyze", "compile"] as const) {
        equal(
          compact.encode(operation, 0n),
          encodeNativeRequest({
            ...classic,
            operation,
            const_steps: 0n,
            fuel: classic.nodeCount,
          }),
          entry.name,
        );
      }
      for (const name of declarationOffsets(classic.root).keys()) {
        const error = new CompilerError({
          code: "test_declaration",
          subject: name,
          message: "declaration location",
        });
        const locations = [classic, compact].map((prepared) => {
          try {
            prepared.translate(error);
          } catch (translated) {
            return diagnostic(translated);
          }
        });
        equal(locations[0], locations[1], `${entry.name}: ${name}`);
      }
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("parallel frontend uses the full grammar's first diagnostic for rejected or ambiguous slices", async () => {
  const frontend = await createSourceFrontend({ prelude: "none", threads: 8 });
  try {
    for (
      const source of [
        `${large}\nimport * as late from "./late"`,
        large.replace("return value_63", "return @u32.add ) 1"),
        large.replace("let value_0", "let ="),
        `${large}\n@attribute\nconst extra = fn () => 1`,
        `${large}\n  const indented = fn () => 1`,
      ]
    ) {
      let expected: ReturnType<typeof diagnostic> | undefined;
      throws(() => frontend.prepare(source), (error) => {
        expected = diagnostic(error);
        return true;
      });
      await rejects(() => frontend.prepareNative(source), (error) => {
        equal(diagnostic(error), expected);
        return true;
      });
    }
    equal(
      (await frontend.prepareNative(large)).encode("compile", 10000n),
      reference(frontend, large),
    );
  } finally {
    frontend.dispose();
  }
});

Deno.test("parallel frontend disposal rejects active and queued work and stays closed", async () => {
  const frontend = await createSourceFrontend({ prelude: "none", threads: 8 });
  const active = frontend.prepareNative(large);
  const queued = frontend.prepareNative(large);
  const checked = Promise.all(
    [active, queued].map((task) => rejects(() => task, /disposed/)),
  );
  await new Promise((resolve) => setTimeout(resolve, 5));
  frontend.dispose();
  await checked;
  await rejects(() => frontend.prepareNative(large), /disposed/);
  throws(() => frontend.prepare(large), /disposed/);
  frontend.dispose();
});

Deno.test("frontend worker creation failures terminate siblings and never fall back silently", async () => {
  const frontend = await createSourceFrontend({ prelude: "none", threads: 8 });
  const original = globalThis.Worker;
  let attempted = 0;
  let terminated = 0;
  const failure = new Error("worker creation failed");
  try {
    globalThis.Worker = class {
      constructor() {
        if (++attempted === 2) throw failure;
      }
      terminate() {
        terminated++;
      }
      postMessage() {}
    } as unknown as typeof Worker;
    // Small requests do not create workers at all.
    const small = "const answer = fn () => 42";
    equal(
      (await frontend.prepareNative(small)).encode("compile", 10000n),
      reference(frontend, small),
    );
    equal(attempted, 0);
    await rejects(
      () => frontend.prepareNative(large),
      (error) => error === failure,
    );
    equal(attempted, 2);
    equal(terminated, 1);
    await rejects(
      () => frontend.prepareNative(large),
      (error) => error === failure,
    );
  } finally {
    globalThis.Worker = original;
    frontend.dispose();
  }
});
