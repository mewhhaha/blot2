// The development tier (`codegenTier: "development"`) is what an edit loop
// such as `pen dev` opens its session with; it skips the optional scalar and
// vector passes. Every release build opens with the default, which must stay
// the optimized tier byte for byte, and development output must run the same.
import { strict as assert } from "node:assert";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
const stdRoot = `${repo}std`;

type Guest = Awaited<ReturnType<typeof instantiateGuest>>;
const loops = (factor: number) =>
  `entry const scaled_sum = fn (input: Array U32) => do:
  let total = input[0]
  for index in 1..input.length:
    total := self + input[index] * ${factor}
  return total
`;
const inputs = [
  Uint32Array.of(0),
  Uint32Array.of(7, 1, 2, 3),
  Uint32Array.from({ length: 67 }, (_, index) => index * 0x01010101),
];
function scaledSum(input: Uint32Array, factor: number) {
  let total = input[0];
  for (let index = 1; index < input.length; index++) {
    total = (total + Math.imul(input[index], factor)) >>> 0;
  }
  return total;
}
const programs: {
  name: string;
  source: () => Promise<string>;
  check: (guest: Guest) => void;
}[] = [
  {
    name: "examples/prelude.blot",
    source: () => Deno.readTextFile(`${repo}examples/prelude.blot`),
    check: (guest) => {
      assert.equal(guest.call("increment", 41), 42);
      assert.equal(guest.call("transform", 20), 42);
      assert.equal(guest.read("const_answer"), 42);
      assert.equal(guest.call("generic_identity", null), 42);
      assert.equal(guest.call("inspect", true), 42);
      assert.equal(guest.call("recover", false), 0);
    },
  },
  {
    name: "examples/syntax.blot",
    source: () => Deno.readTextFile(`${repo}examples/syntax.blot`),
    check: (guest) => {
      assert.equal(guest.call("lazy_fallback", null), 42);
      assert.equal(guest.call("factorial", 5), 120);
      assert.equal(guest.call("recursive_example", 8), 40320);
      assert.equal(guest.call("matching_example", null), 42);
      assert.equal(guest.call("vector_example", null), 50);
      assert.equal(guest.call("array_snapshot", null), 22);
      assert.equal(guest.call("provider_example", null), 42);
    },
  },
  {
    name: "loops",
    source: () => Promise.resolve(loops(3)),
    check: (guest) => {
      for (const input of inputs) {
        assert.equal(guest.call("scaled_sum", input), scaledSum(input, 3));
      }
    },
  },
];

async function build(
  options: ZigProjectCompilerOptions,
  sources: Record<string, string>,
) {
  const compiler = await createZigProjectCompiler(options);
  try {
    const built = await compiler.build({ sources });
    assert(built.success, JSON.stringify(built));
    return built.bytes;
  } finally {
    await compiler.dispose();
  }
}
async function run(bytes: Uint8Array<ArrayBuffer>, check: (guest: Guest) => void) {
  const guest = await instantiateGuest(bytes);
  try {
    check(guest);
  } finally {
    guest.dispose();
  }
}

Deno.test("development tier leaves default builds optimized and runs the same programs", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-development-tier-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    stdRoot,
    cacheDirectory: false as const,
  };
  try {
    let differs = 0;
    for (const program of programs) {
      const sources = { [entry]: await program.source() };
      const release = await build(options, sources);
      const optimized = await build({ ...options, codegenTier: "optimized" }, sources);
      const development = await build({ ...options, codegenTier: "development" }, sources);
      assert.deepEqual(release, optimized, program.name);
      if (release.length !== development.length || release.some((byte, index) => byte !== development[index])) differs++;
      await run(release, program.check);
      await run(development, program.check);
    }
    // The tier reaches code generation: some program builds differently.
    assert(differs > 0);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("a development edit loop matches fresh development builds and runs each revision", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-development-loop-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable,
    entry,
    prelude,
    stdRoot,
    codegenTier: "development" as const,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const factor of [3, 4, 3, 5]) {
      const sources = { [entry]: loops(factor) };
      const built = await retained.build({ sources });
      assert(built.success, JSON.stringify(built));
      assert.deepEqual(built.bytes, await build(options, sources), `factor ${factor}`);
      await run(built.bytes, (guest) => {
        for (const input of inputs) {
          assert.equal(guest.call("scaled_sum", input), scaledSum(input, factor));
        }
      });
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
