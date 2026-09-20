import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createBackgroundCompiler } from "./background_compiler.ts";
import { CompilationFailure } from "./compile_protocol.ts";

const source = `#[resource]
data Clock = Clock U32
export fn tick () => do:
  use wrapped <- @ecs.get Clock
  let Clock value = wrapped
  use @ecs.set (Clock (value + 1))
  return ()
`;

Deno.test("background parser/native compiler keeps host timers running and survives invalid edits", async () => {
  const compiler = createBackgroundCompiler();
  try {
    const first = await compiler.compile(source);
    ok(first.artifact.bytes.length > 0);
    const larger = source + Array.from({ length: 64 }, (_, index) => `
export fn system_${index} () => do:
  use wrapped <- @ecs.get Clock
  let Clock value = wrapped
  use @ecs.set (Clock (value + ${index}))
  return ()
`).join("");
    let ticks = 0;
    const timer = setInterval(() => ticks++, 1);
    try {
      await compiler.compile(larger);
    } finally {
      clearInterval(timer);
    }
    ok(
      ticks > 1,
      `host timers ran only ${ticks} times during background compilation`,
    );
    await rejects(
      compiler.compile("export fn broken () => missing\n", "live-edit.blot"),
      (error) =>
        error instanceof CompilationFailure && error.diagnostic &&
        error.message.includes("live-edit.blot:1:"),
    );
    const recovered = await compiler.compile(source);
    equal(recovered.artifact.bytes, first.artifact.bytes);
  } finally {
    await compiler.close();
  }
});

Deno.test("closing background compiler rejects startup/queued work and is idempotent", async () => {
  const compiler = createBackgroundCompiler();
  const first = compiler.compile(source);
  const second = compiler.compile(source);
  const rejected = Promise.all([
    rejects(first, /closed/),
    rejects(second, /closed/),
  ]);
  const close = compiler.close();
  equal(compiler.close(), close);
  await Promise.all([close, rejected]);
  await rejects(compiler.compile(source), /closed/);
});
