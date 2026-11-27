import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const compiler = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const std = new URL("../../std", import.meta.url).pathname;

const tree = `
const grow = func (count: U32) => return do:
  let root: Link = $End
  for index in 0..count:
    root := $Next (self, index)
  break root
io const run = func (count: U32) => return do:
  let original = grow count
  let changed = $Next (original, 8192)
  let saved = case original of
    $Next (_, value) => value
    _ => 0
  break case changed of
    $Next (tail, value) => case tail of
      $Next (_, latest) => @u32.add value (@u32.add latest saved)
      _ => 0
    _ => 0
io const memory = func () : Array U32 => return #[]
`;

function inspect(bytes: Uint8Array<ArrayBuffer>) {
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  const run = raw.run as CallableFunction;
  assert.equal(run(8192), 8192 + 8191 * 2);
  const memory = raw["squid:memory"] as WebAssembly.Memory;
  const warm = memory.buffer.byteLength;
  for (let iteration = 0; iteration < 8; iteration++) {
    assert.equal(run(4096), 8192 + 4095 * 2);
    assert.equal(memory.buffer.byteLength, warm);
  }
}

/** Builds a multi-module project; `main.sq` is the entry. */
async function buildProject(
  files: Record<string, string>,
  options: { std?: boolean } = {},
): Promise<Uint8Array<ArrayBuffer>> {
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "squid-acyclic-owner-",
  });
  try {
    for (const [name, text] of Object.entries(files)) {
      await Deno.writeTextFile(`${directory}/${name}`, text);
    }
    const output = `${directory}/main.wasm`;
    const result = await new Deno.Command(compiler, {
      args: [
        "build-project",
        `${directory}/main.sq`,
        output,
        ...(options.std
          ? ["--std-root", std, "--prelude", `${std}/prelude.sq`]
          : []),
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(result.stdout);
    assert(result.success, text + new TextDecoder().decode(result.stderr));
    const metrics = text.trim().split("\n").map((line) => JSON.parse(line))
      .at(-1);
    assert.equal(metrics.memory.live_bytes, 0);
    return await Deno.readFile(output);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

const foreignTree = (link: string) =>
  buildProject({
    "link.sq": link,
    "main.sq": 'import * as link from "./link"\n' +
      tree.replaceAll("Link", "link.Link").replaceAll("$End", "$link.End")
        .replaceAll("$Next", "$link.Next"),
  });

Deno.test("immutable source trees preserve aliases", async () => {
  await compileAndRun(
    "type Link is data = $End | $Next (Link, U32)\n" + tree,
    (_, bytes) => inspect(bytes),
  );
});

Deno.test("foreign constructor definitions preserve aliases", async () => {
  inspect(await foreignTree("type Link is data = $End | $Next (Link, U32)\n"));
});

Deno.test("foreign constructors with a closure variant preserve aliases", async () => {
  inspect(
    await foreignTree(
      "type Link is data = $End | $Next (Link, U32) | $Later (Unit -> U32)\n",
    ),
  );
});

Deno.test("temporary containers of scalar elements keep their results", async () => {
  const frames = 100;
  await compileAndRun(
    `import * as array from "std/array"
type Scalar is data = $Scalar { a: U32, b: F32 }
io const run = func (frames: U32) : U32 => return do:
  let total = 0
  for frame in 0..frames:
    let items = #[$Scalar { a: index, b: 1.0 } | index <- array.generate 4000 identity]
    total := self + items[3].a
  break total
io const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      assert.equal((raw.run as CallableFunction)(frames), 3 * frames);
    },
    { stdRoot: std },
  );
});

Deno.test("containers of closure-capable elements keep their results", async () => {
  const frames = 100;
  await compileAndRun(
    `import * as array from "std/array"
type Scalar is data = $Scalar { a: U32, b: F32 }
type Item is data = $Plain Scalar | $Lazy (Unit -> U32)
const value = func (item: Item) : U32 => return case item of
  $Plain ($Scalar { a, b }) => a
  $Lazy later => later ()
io const run = func (frames: U32) : U32 => return do:
  let total = 0
  for frame in 0..frames:
    let items = #[$Plain ($Scalar { a: index, b: 1.0 }) | index <- array.generate 4000 identity]
    total := self + value items[3]
  break total
io const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      assert.equal((raw.run as CallableFunction)(frames), 3 * frames);
    },
    { stdRoot: std },
  );
});

// Issue #16: per-frame draw records built in nested comprehensions and
// flattened, with math types in another module and Maybe/Array fields.
const gmath = `type Vec4 is data = $Vec4 { x: F32, y: F32, z: F32, w: F32 }
type Mat4 is data = $Mat4 { x: Vec4, y: Vec4, z: Vec4, w: Vec4 }
const Mat4.translation = func (x: F32) => return func (y: F32) => return func (z: F32) => return $Mat4 {
  x: $Vec4 { x: 1.0, y: 0.0, z: 0.0, w: 0.0 },
  y: $Vec4 { x: 0.0, y: 1.0, z: 0.0, w: 0.0 },
  z: $Vec4 { x: 0.0, y: 0.0, z: 1.0, w: 0.0 },
  w: $Vec4 { x: x, y: y, z: z, w: 1.0 },
}
`;
const frames = `import * as array from "std/array"
import * as m from "./gmath"
type Stack is data = $Stack { x: F32, z: F32, count: U32 }
type Draw is data = $Draw { mesh: U32, material: U32, matrix: m.Mat4, parameters: Maybe m.Vec4, extra: Array m.Vec4 }
const draw_of = func (stack: Stack) => return func (above: U32) => return $Draw {
  mesh: 1,
  material: above,
  matrix: m.Mat4.translation stack.x (U32.to_f32 above) stack.z,
  parameters: $Some ($m.Vec4 { x: stack.x, y: 0.0, z: stack.z, w: 1.0 }),
  extra: #[],
}
const stack_draws = func (stack: Stack) => return
  #[draw_of stack above | above <- array.generate stack.count identity]
const frame = func (stacks: Array Stack) => return do:
  let parts = #[part | stack <- stacks, part <- stack_draws stack]
  let origin = $Stack { x: 0.0, z: 0.0, count: 1 }
  let head = #[draw_of origin 0]
  let payload = array.concat head parts
  let flat = array.flatten #[{start: 0, count: head.length}, {start: head.length, count: parts.length}] payload
  let sum = 0
  for d in flat:
    sum := self + d.material
  break sum
io const run = func (frames: U32) : U32 => return do:
  let stacks = array.generate 64 (func i => return $Stack { x: U32.to_f32 i, z: 0.5, count: 2 })
  let total = 0
  for f in 0..frames:
    total := self + frame stacks
  break total
io const memory = func () : Array U32 => return #[]
`;

// Direct backend gap: a loop that calls an allocating function is not reclaimed per iteration, so 100 frames exhaust memory (tasks/DELETE_SCOPED.md).
Deno.test.ignore("frame draws with foreign math, Maybe and Array fields keep their results", async () => {
  const bytes = await buildProject(
    { "gmath.sq": gmath, "main.sq": frames },
    {
      std: true,
    },
  );
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  const run = raw.run as CallableFunction;
  // Each stack draws materials 0 and 1; the head draw has material 0.
  assert.equal(run(200), 64 * 200);
  const memory = raw["squid:memory"] as WebAssembly.Memory;
  const warm = memory.buffer.byteLength;
  for (let round = 0; round < 4; round++) {
    assert.equal(run(200), 64 * 200);
    assert.equal(memory.buffer.byteLength, warm, "frames reuse their storage");
  }
});
