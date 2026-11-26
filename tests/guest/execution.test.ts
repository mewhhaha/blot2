import { instantiateGuest } from "../../host/guest.ts";

const compiler = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const buildDir = new URL("../../build", import.meta.url).pathname;
const decode = new TextDecoder();

function equal(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
}

async function traps(run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (error) {
    if (error instanceof WebAssembly.RuntimeError) return;
    throw error;
  }
  throw new Error("Expected a WebAssembly trap");
}

async function withCompilation(
  source: string,
  run: (bytes: Uint8Array, metrics: Record<string, unknown>) => Promise<void>,
  options: { prelude?: string } = {},
): Promise<void> {
  const dir = await Deno.makeTempDir({
    dir: buildDir,
    prefix: "zig-native-e2e-",
  });
  try {
    const input = `${dir}/program.blot`;
    const output = `${dir}/program.wasm`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(compiler, {
      args: ["build", input, output, ...(options.prelude ? ["--prelude", options.prelude] : [])],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = decode.decode(result.stdout);
    if (!result.success) {
      throw new Error(`${text}\n${decode.decode(result.stderr)}`);
    }
    const records = text.trim().split("\n").map((line) => JSON.parse(line));
    const metrics = records.find((record) => record.kind === "compilation");
    equal(metrics.success, true);
    equal(metrics.memory.live_bytes, 0);
    const bytes = await Deno.readFile(output);
    equal(WebAssembly.validate(bytes), true);
    await run(bytes, metrics);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("native source executes through the existing guest ABI", async () => {
  await withCompilation(
    `
const identity = func value => return value
const add = func left => return func right => return @u32.add left right
io const maximum: U32 = 0xFFFF_FFFF
io const answer = func () : U32 => return add (identity 20) (identity 22)
io const floating = func (value: F32) : F32 => return identity value
io const capped = func (value: U32) : U32 => return do:
  if @u32.lt value 42:
    break value
  break 42
io const nested = func () : U32 => return do:
  let inner = do:
    break 20
  break @u32.add inner 22
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.read("maximum"), 0xFFFF_FFFF);
        equal(guest.call("answer", null), 42);
        equal(guest.call("floating", 1.23456789), Math.fround(1.23456789));
        equal(guest.call("capped", 17), 17);
        equal(guest.call("capped", 80), 42);
        equal(guest.call("nested", null), 42);
      } finally {
        guest.dispose();
      }
    },
  );
});

Deno.test("native recursive calls and unsigned overflow preserve behavior", async () => {
  await withCompilation(
    `
const factorial = func (value: U32) : U32 => return
  if @u32.lt value 2 then 1 else @u32.mul value (factorial (@u32.sub value 1))
io const run = func (value: U32) : U32 => return factorial value
io const wrap = func (value: U32) : U32 => return @u32.add value 1
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        for (
          const [input, expected] of [[0, 1], [1, 1], [5, 120], [10, 3628800]]
        ) {
          equal(guest.call("run", input), expected);
        }
        equal(guest.call("wrap", 0xFFFF_FFFF), 0);
      } finally {
        guest.dispose();
      }
    },
  );
});

Deno.test("native logical operators skip a trapping right operand", async () => {
  await withCompilation(
    `
io const conjunction = func (left: Bool) : Bool => return
  left and @u32.eq (@u32.div 1 0) 0
io const disjunction = func (left: Bool) : Bool => return
  left or @u32.eq (@u32.div 1 0) 0
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.call("conjunction", false), false);
        equal(guest.call("disjunction", true), true);
        let trapped = false;
        try {
          guest.call("conjunction", true);
        } catch {
          trapped = true;
        }
        equal(trapped, true);
        equal(guest.call("disjunction", true), true);
      } finally {
        guest.dispose();
      }
    },
    { prelude: new URL("../../std/prelude.blot", import.meta.url).pathname },
  );
});

Deno.test("native branch rebinding preserves immutable aliases", async () => {
  await withCompilation(
    `
io const run = func (enabled: Bool) : U32 => return do:
  let value = 20
  let saved = value
  if enabled:
    value := 40
  break @u32.add value saved
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.call("run", false), 40);
        equal(guest.call("run", true), 60);
      } finally {
        guest.dispose();
      }
    },
  );
});

Deno.test("native F32 conversion uses saturating Wasm behavior", async () => {
  await withCompilation(
    `
io const convert = func (value: F32) : U32 => return @f32.to_u32 value
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        for (
          const [input, expected] of [
            [NaN, 0],
            [-Infinity, 0],
            [-1, 0],
            [-0, 0],
            [3.75, 3],
            [4294967296, 0xFFFF_FFFF],
            [Infinity, 0xFFFF_FFFF],
          ]
        ) equal(guest.call("convert", input), expected);
      } finally {
        guest.dispose();
      }
    },
  );
});

// Constants are computed at instantiation, so a trapping entry constant
// compiles and its module traps when instantiated.
Deno.test("reachable constant traps compile and trap at instantiation", async () => {
  await withCompilation(
    "io const failure = @u32.div 1 0\nio const answer = func () : U32 => return 42\n",
    async (bytes) => {
      await traps(async () => (await instantiateGuest(bytes)).dispose());
    },
  );
});

Deno.test("typed core evaluates pure recursive functions and branch merges at compile time", async () => {
  await withCompilation(
    `
const identity = func value => return value
const factorial = func (value: U32) : U32 => return
  if @u32.lt value 2 then 1 else @u32.mul value (factorial (@u32.sub value 1))
const branch = func (enabled: Bool) : U32 => return do:
  let value = 20
  let saved = value
  if enabled:
    value := 40
  break @u32.add value saved
io const answer = identity (factorial 5)
io const yes = branch true
io const no = branch false
io const floating = identity 1.25
io const safe = if false then @u32.div 1 0 else 42
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.read("answer"), 120);
        equal(guest.read("yes"), 60);
        equal(guest.read("no"), 40);
        equal(guest.read("floating"), 1.25);
        equal(guest.read("safe"), 42);
      } finally {
        guest.dispose();
      }
    },
  );
});

Deno.test("named constant references compile and trap when the program reads them", async () => {
  for (
    const [entry, read] of [
      ["io const value = if true then bad else 42", true],
      ["io const value = func () : U32 => return if true then bad else 42", false],
    ] as const
  ) {
    await withCompilation(`const bad = @u32.div 1 0\n${entry}\n`, async (bytes) => {
      await traps(async () => {
        const guest = await instantiateGuest(bytes);
        try {
          if (read) guest.read("value");
          else guest.call("value", null);
        } finally {
          guest.dispose();
        }
      });
    });
  }
});

Deno.test("native compiler checks unused definitions without executing their constants", async () => {
  await withCompilation(
    `
const unused = @u32.div 1 0
io const answer = func () : U32 => return 42
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.call("answer", null), 42);
      } finally {
        guest.dispose();
      }
    },
  );
});
