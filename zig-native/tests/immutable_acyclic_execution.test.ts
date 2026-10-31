import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const std = new URL("../../std", import.meta.url).pathname;

const tree = `
const grow = func (count: U32) => return do:
  let root: Link = $End
  for index in 0..count:
    root := $Next (self, index)
  break root
entry const run = func (count: U32) => return do:
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
entry const memory = func () : Array U32 => return #[]
`;

type Exports = Record<string, unknown>;
const metric = (raw: Exports, name: string) =>
  Number((raw[`blot:${name}`] as WebAssembly.Global).value);

function inspect(bytes: Uint8Array<ArrayBuffer>, acyclic: boolean) {
  const module = new WebAssembly.Module(bytes);
  assert.deepEqual([
    ...new Uint8Array(
      WebAssembly.Module.customSections(module, "blot:ownership")[0],
    ),
  ], [2, 2, 0]);
  const raw = new WebAssembly.Instance(module).exports;
  const count = (name: string) => metric(raw, name);
  const run = raw.run as CallableFunction;
  assert.equal(run(8192), 8192 + 8191 * 2);
  const memory = raw["blot:memory"] as WebAssembly.Memory;
  const warm = memory.buffer.byteLength;
  const destroyed = count("rc_destroyed");
  for (let iteration = 0; iteration < 8; iteration++) {
    assert.equal(run(4096), 8192 + 4095 * 2);
    assert.equal(memory.buffer.byteLength, warm);
    assert.equal(count("rc_roots"), 0);
    assert.equal(count("rc_leases"), 0);
  }
  assert(count("rc_destroyed") > destroyed, "aliases must retire iteratively");
  if (acyclic) {
    for (const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]) {
      assert.equal(count(name), 0, "immutable trees must avoid trial scans");
    }
  } else {
    assert(
      count("cycle_vertices") > 0,
      "cycle-capable shapes must decline the proof",
    );
  }
  (raw["blot:ownership_leave"] as CallableFunction)(2);
}

/** Builds a multi-module project; `main.blot` is the entry. */
async function buildProject(
  files: Record<string, string>,
  options: { std?: boolean } = {},
): Promise<Uint8Array<ArrayBuffer>> {
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "blot-acyclic-owner-",
  });
  try {
    for (const [name, text] of Object.entries(files)) {
      await Deno.writeTextFile(`${directory}/${name}`, text);
    }
    const output = `${directory}/main.wasm`;
    const result = await new Deno.Command(compiler, {
      args: [
        "build-project",
        `${directory}/main.blot`,
        output,
        ...(options.std
          ? ["--std-root", std, "--prelude", `${std}/prelude.blot`]
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
    "link.blot": link,
    "main.blot": 'import * as link from "./link"\n' +
      tree.replaceAll("Link", "link.Link").replaceAll("$End", "$link.End")
        .replaceAll("$Next", "$link.Next"),
  });

Deno.test("immutable source trees preserve aliases and skip all trial work", async () => {
  await compileAndRun(
    "type Link is data = $End | $Next (Link, U32)\n" + tree,
    (_, bytes) => inspect(bytes, true),
  );
});

Deno.test("foreign constructor definitions keep the immutable proof", async () => {
  inspect(
    await foreignTree("type Link is data = $End | $Next (Link, U32)\n"),
    true,
  );
});

Deno.test("foreign constructors that can close a cycle decline the proof", async () => {
  // The unused closure variant alone makes every Link cycle-capable.
  inspect(
    await foreignTree(
      "type Link is data = $End | $Next (Link, U32) | $Later (Unit -> U32)\n",
    ),
    false,
  );
});

Deno.test("temporary containers of proven elements skip candidacy", async () => {
  const frames = 100;
  await compileAndRun(
    `import * as array from "std/array"
type Scalar is data = $Scalar { a: U32, b: F32 }
entry const run = func (frames: U32) : U32 => return do:
  let total = 0
  for frame in 0..frames:
    let items = #[$Scalar { a: index, b: 1.0 } | index <- array.generate 4000 identity]
    total := self + items[3].a
  break total
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      assert.equal((raw.run as CallableFunction)(frames), 3 * frames);
      // The List builder, its tree and the converted Array all carry the
      // element proof, so no temporary becomes a candidate.
      for (const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]) {
        assert.equal(metric(raw, name), 0, name);
      }
    },
    { stdRoot: std },
  );
});

Deno.test("trial passes skip proven payloads of candidate elements", async () => {
  const frames = 100;
  await compileAndRun(
    `import * as array from "std/array"
type Scalar is data = $Scalar { a: U32, b: F32 }
type Item is data = $Plain Scalar | $Lazy (Unit -> U32)
const value = func (item: Item) : U32 => return case item of
  $Plain ($Scalar { a, b }) => a
  $Lazy later => later ()
entry const run = func (frames: U32) : U32 => return do:
  let total = 0
  for frame in 0..frames:
    let items = #[$Plain ($Scalar { a: index, b: 1.0 }) | index <- array.generate 4000 identity]
    total := self + value items[3]
  break total
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      assert.equal((raw.run as CallableFunction)(frames), 3 * frames);
      assert(
        metric(raw, "cycle_passes") > 0,
        "Item containers stay candidates",
      );
      // Each Item cell is one vertex with one edge to its proven Scalar,
      // which discovery does not visit; visiting it would equalize the two.
      const vertices = metric(raw, "cycle_vertices");
      const edges = metric(raw, "cycle_edges");
      assert(vertices * 4 < edges * 3, `${vertices} vertices, ${edges} edges`);
      assert.equal(metric(raw, "cycle_bytes"), 0);
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
type Draw is data = $Draw { mesh: U32, material: U32, matrix: m.Mat4, parameters: Maybe m.Vec4, extra: Array m.Vec4, path: List m.Vec4 }
const draw_of = func (stack: Stack) => return func (above: U32) => return $Draw {
  mesh: 1,
  material: above,
  matrix: m.Mat4.translation stack.x (U32.to_f32 above) stack.z,
  parameters: $Some ($m.Vec4 { x: stack.x, y: 0.0, z: stack.z, w: 1.0 }),
  extra: #[],
  path: [$m.Vec4 { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }],
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
entry const run = func (frames: U32) : U32 => return do:
  let stacks = array.generate 64 (func i => return $Stack { x: U32.to_f32 i, z: 0.5, count: 2 })
  let total = 0
  for f in 0..frames:
    total := self + frame stacks
  break total
entry const memory = func () : Array U32 => return #[]
`;

Deno.test("frame draws with foreign math, Maybe, Array and List fields skip cycle work", async () => {
  const bytes = await buildProject(
    { "gmath.blot": gmath, "main.blot": frames },
    {
      std: true,
    },
  );
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  const run = raw.run as CallableFunction;
  // Each stack draws materials 0 and 1; the head draw has material 0.
  assert.equal(run(200), 64 * 200);
  const memory = raw["blot:memory"] as WebAssembly.Memory;
  const warm = memory.buffer.byteLength;
  for (let round = 0; round < 4; round++) {
    assert.equal(run(200), 64 * 200);
    assert.equal(memory.buffer.byteLength, warm, "frames reuse their storage");
  }
  for (const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]) {
    assert.equal(metric(raw, name), 0, name);
  }
  assert(metric(raw, "rc_destroyed") > 0);
});

Deno.test("List copies, slices, concatenations and conversions keep the element proof", async () => {
  await compileAndRun(
    `import * as list from "std/list"
type Point is data = $Point { x: U32, y: Maybe U32 }
type Bag is data = $Bag { items: List Point, extra: Array Point }
const point = func (index: U32) => return $Point { x: index, y: $Some index }
const sum = func (values: List Point) : U32 => return list.fold_left (func total => return func (p: Point) => return @u32.add total p.x) 0 values
entry const run = func (frames: U32) : U32 => return do:
  let total = 0
  for frame in 0..frames:
    let base = list.generate 600 point
    let grown = list.append (point 9) base
    let joined = list.concat base grown
    let middle = list.slice 100 700 joined
    let even = list.filter (func (p: Point) => return @u32.rem p.x 2 == 0) middle
    let bag = $Bag { items: even, extra: list.to_array middle }
    let back = list.from_array bag.extra
    total := self + sum back + sum bag.items + base.length
  break total
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes))
        .exports;
      const run = raw.run as CallableFunction;
      // middle is x = 100..599 then 0..199; even keeps its even values.
      const perFrame = 174750 + 19900 + (87250 + 9900) + 600;
      assert.equal(run(20), 20 * perFrame);
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      const warm = memory.buffer.byteLength;
      for (let round = 0; round < 4; round++) {
        assert.equal(run(20), 20 * perFrame);
        assert.equal(memory.buffer.byteLength, warm);
      }
      for (const name of ["cycle_passes", "cycle_vertices", "cycle_edges"]) {
        assert.equal(metric(raw, name), 0, name);
      }
    },
    { stdRoot: std },
  );
});
