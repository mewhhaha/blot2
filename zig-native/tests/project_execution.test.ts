import { instantiateGuest } from "../../compiler/guest.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const buildDir = new URL("../../build", import.meta.url).pathname;
function equal(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}
async function project(
  files: Record<string, string>,
  run: (bytes: Uint8Array, metrics: Record<string, any>) => Promise<void>,
  options: { prelude?: string } = {},
): Promise<void> {
  const dir = await Deno.makeTempDir({
    dir: buildDir,
    prefix: "zig-native-project-e2e-",
  });
  try {
    for (const [name, text] of Object.entries(files)) {
      await Deno.writeTextFile(`${dir}/${name}.blot`, text);
    }
    const output = `${dir}/program.wasm`;
    const built = await new Deno.Command(compiler, {
      args: ["build-project", `${dir}/main.blot`, output, ...(options.prelude ? ["--prelude", options.prelude] : [])],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(built.stdout);
    if (!built.success) {
      throw new Error(`${text}\n${new TextDecoder().decode(built.stderr)}`);
    }
    const metrics = text.trim().split("\n").map((line) => JSON.parse(line)).at(
      -1,
    );
    equal(metrics.success, true);
    equal(metrics.memory.live_bytes, 0);
    const bytes = await Deno.readFile(output);
    equal(WebAssembly.validate(bytes), true);
    await run(bytes, metrics);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("project imports preserve quantified written rows at independent effect and result instances", async () => {
  await project({
    main: `import { invoke } from "./library"
effect Read: Unit -> U32
effect Measure: Unit -> F32
const reader = @effect.provider Read (fn () => 42)
const measure = @effect.provider Measure (fn () => 42.5)
entry const integer = fn () => do reader:
  return invoke (fn () => Read ())
entry const floating = fn () => do measure:
  return invoke (fn () => Measure ())
`,
    library:
      `const invoke: (Unit -> a ! {| e}) -> a ! {| e} = fn callback => callback ()
`,
  }, async (bytes) => {
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("integer", null), 42);
      equal(guest.call("floating", null), 42.5);
    } finally {
      guest.dispose();
    }
  });
});

Deno.test("reflection preserves imported function provenance and operation identities", async () => {
  await project({
    main: `import {read, Read, effects, descriptor} from "./library"
import * as library from "./library"
entry const count = @effect.count (@effect.of read)
entry const qualified = @effect.count (@effect.of library.read)
entry const present = @effect.has effects descriptor
entry const same = @effect.same descriptor (@effect.descriptor Read)
`,
    library: `effect Read: Unit -> U32
const read = fn () => @panic "imported reflected function invoked"
const effects = @effect.of read
const descriptor = @effect.descriptor Read
`,
  }, async (bytes) => {
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.read("count"), 0);
      equal(guest.read("qualified"), 0);
      equal(guest.read("present"), false);
      equal(guest.read("same"), true);
    } finally {
      guest.dispose();
    }
  });
});

Deno.test("builtin State shares exact identities across imported helpers and separates generic instances", async () => {
  await project({
    main: `import { read, write, Cell } from "./library"
entry const answer = fn () => do:
  let (#Cell final, (#Cell floating, value)) = @state.run (#Cell 40) (fn () =>
    @state.run (#Cell 1.0) (fn () => do:
      use integer <- read (fn () => #Cell 0)
      let #Cell count = integer
      use amount <- read (fn () => #Cell 0.0)
      let #Cell fraction = amount
      use write (#Cell (@u32.add count 1))
      use write (#Cell (@f32.add fraction 0.5))
      return count))
  return @f32.add (@u32.to_f32 final) (@f32.add floating (@u32.to_f32 value))
`,
    library: `data Cell value = #Cell value
const read = fn witness => @state.get witness
const write = fn value => @state.set value
`,
  }, async (bytes) => {
    const guest = await instantiateGuest(bytes);
    try {
      for (let index = 0; index < 100; index++) {
        equal(guest.call("answer", null), 82.5);
      }
    } finally {
      guest.dispose();
    }
  });
});

Deno.test("project emits shared generic producers across a diamond after frontend teardown", async () => {
  await project({
    main: `import * as left from "./left"
import * as right from "./right"
import { identity as id } from "./shared"
entry const integer = fn (value: U32) -> U32 => left.twice (id value)
entry const floating = fn (value: F32) -> F32 => right.twice (id value)
entry const answer = left.answer
`,
    left: `import * as shared from "./shared"
const twice = fn (value: U32) -> U32 => shared.twice (shared.identity value)
const answer = shared.answer
`,
    right: `import * as shared from "./shared"
const twice = fn (value: F32) -> F32 => shared.twice (shared.identity value)
`,
    shared: `const identity = fn value => value
const twice = fn value => value + value
const answer = 42
`,
  }, async (bytes, metrics) => {
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("integer", 21), 42);
      equal(guest.call("integer", 0xFFFFFFFF), 0xFFFFFFFE);
      equal(guest.call("floating", 1.25), 2.5);
      equal(guest.read("answer"), 42);
      equal(metrics.files, 5);
      const preludeSource = await Deno.readTextFile(new URL("../../std/prelude.blot", import.meta.url));
      const preludeBodies = [...preludeSource.matchAll(/^(?:const|let) /gm)].length;
      equal(metrics.body_elaborations, 9 + preludeBodies);
      equal(metrics.body_lowerings, 9 + preludeBodies);
      equal(metrics.code_instances, 4);
    } finally {
      guest.dispose();
    }
  }, { prelude: new URL("../../std/prelude.blot", import.meta.url).pathname });
});

Deno.test("project aliases and imported custom fixity preserve producer identities", async () => {
  await project({
    main: `import * as arithmetic from "./arithmetic"
import { identity } from "./arithmetic"
infixl 60 (+) = arithmetic.subtract
const alias = arithmetic.identity
entry const identity_entry = alias
entry const subtract_entry = fn (arithmetic: U32) -> U32 => 20 + arithmetic
entry const grouped = fn (value: U32) -> U32 => (arithmetic).identity value
`,
    arithmetic: `const identity = fn (value: U32) -> U32 => value
const subtract = fn left => fn right => @u32.sub left right
`,
  }, async (bytes) => {
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("identity_entry", 42), 42);
      equal(guest.call("subtract_entry", 22), 0xFFFFFFFE);
      equal(guest.call("grouped", 37), 37);
    } finally {
      guest.dispose();
    }
  });
});
