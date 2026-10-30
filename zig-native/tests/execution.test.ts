import { instantiateGuest } from "../../compiler/guest.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const buildDir = new URL("../../build", import.meta.url).pathname;
const decode = new TextDecoder();

function equal(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
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
entry const maximum: U32 = 0xFFFF_FFFF
entry const answer = func () : U32 => return add (identity 20) (identity 22)
entry const floating = func (value: F32) : F32 => return identity value
entry const capped = func (value: U32) : U32 => return do:
  if @u32.lt value 42:
    break value
  break 42
entry const nested = func () : U32 => return do:
  let inner = do:
    break 20
  break @u32.add inner 22
`,
    async (bytes, metrics) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.read("maximum"), 0xFFFF_FFFF);
        equal(guest.call("answer", null), 42);
        equal(guest.call("floating", 1.23456789), Math.fround(1.23456789));
        equal(guest.call("capped", 17), 17);
        equal(guest.call("capped", 80), 42);
        equal(guest.call("nested", null), 42);
        equal((metrics.stats as Record<string, unknown>).code_instances, 4);
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
entry const run = func (value: U32) : U32 => return factorial value
entry const wrap = func (value: U32) : U32 => return @u32.add value 1
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
entry const conjunction = func (left: Bool) : Bool => return
  left and @u32.eq (@u32.div 1 0) 0
entry const disjunction = func (left: Bool) : Bool => return
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

Deno.test("native source fixity targets are ordinary functions", async () => {
  await withCompilation(
    `
infixl 60 (+) = subtract
const subtract = func left => return func right => return @u32.sub left right
entry const custom = func () : U32 => return 20 + 22
`,
    async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        equal(guest.call("custom", null), 0xFFFF_FFFE);
      } finally {
        guest.dispose();
      }
    },
  );
});

Deno.test("native branch rebinding preserves immutable aliases", async () => {
  await withCompilation(
    `
entry const run = func (enabled: Bool) : U32 => return do:
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
entry const convert = func (value: F32) : U32 => return @f32.to_u32 value
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

Deno.test("native compilation diagnoses reachable constant traps", async () => {
  const dir = await Deno.makeTempDir({
    dir: buildDir,
    prefix: "zig-native-negative-",
  });
  try {
    for (
      const [declaration, code] of [
        ["entry const failure = @u32.div 1 0", "integer_divide_by_zero"],
      ]
    ) {
      const source = `${dir}/invalid.blot`;
      const output = `${dir}/${code}.wasm`;
      await Deno.writeTextFile(
        source,
        `${declaration}\nentry const answer = func () : U32 => return 42\n`,
      );
      const result = await new Deno.Command(compiler, {
        args: ["build", source, output],
        stdout: "piped",
        stderr: "piped",
      }).output();
      equal(result.code, 1);
      const records = decode.decode(result.stdout).trim().split("\n").map((
        line,
      ) => JSON.parse(line));
      equal(records[0].stage, "emit");
      equal(records[0].code, code);
      equal(records.at(-1).success, false);
      equal(records.at(-1).memory.live_bytes, 0);
      let absent = false;
      try {
        await Deno.stat(output);
      } catch (error) {
        absent = error instanceof Deno.errors.NotFound;
      }
      equal(absent, true);
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
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
entry const answer = identity (factorial 5)
entry const yes = branch true
entry const no = branch false
entry const floating = identity 1.25
entry const safe = if false then @u32.div 1 0 else 42
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

Deno.test("named constant references in dead branches retain compilation dependencies", async () => {
  const dir = await Deno.makeTempDir({
    dir: buildDir,
    prefix: "zig-native-reachability-",
  });
  try {
    for (
      const entry of [
        "entry const value = if false then bad else 42",
        "entry const value = func () : U32 => return if false then bad else 42",
      ]
    ) {
      const input = `${dir}/invalid.blot`;
      await Deno.writeTextFile(input, `const bad = @u32.div 1 0\n${entry}\n`);
      const result = await new Deno.Command(compiler, {
        args: ["build", input, `${dir}/invalid.wasm`],
        stdout: "piped",
        stderr: "piped",
      }).output();
      equal(result.code, 1);
      const records = decode.decode(result.stdout).trim().split("\n").map((
        line,
      ) => JSON.parse(line));
      equal(records[0].code, "integer_divide_by_zero");
      equal(records.at(-1).memory.live_bytes, 0);
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("native compiler checks unused definitions without executing their constants", async () => {
  await withCompilation(
    `
const unused = @u32.div 1 0
entry const answer = func () : U32 => return 42
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
