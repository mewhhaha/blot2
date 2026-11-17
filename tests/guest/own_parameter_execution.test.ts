import { instantiateGuest } from "../../host/guest.ts";
import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// A parameter marked `own` is taken over (tasks/MEMORY_MODEL.md rule 4): the
// function updates it in place, the caller's name is spent, and the result
// is the caller's alone. Only a top-level named function can take one yet.
const compiler = Deno.args[0] ?? new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const buildDir = new URL("../../build", import.meta.url).pathname;

const declarations = `type World is data = $World { counts: Array U32, size: U32 }
func damage (world: own World) -> (index: U32): World => return do:
  world.counts[index] := world.counts[index] + 1
  break world
func fill (rows: own Array U32) -> (n: U32): Array U32 => return do:
  for i in 0..rows.length:
    rows[i] := n
  break rows
const first = func (rows: Array U32) => return rows[0]
func World.grow (world: own World) -> (amount: U32): World => return do:
  world.size := world.size + amount
  world.counts[0] := world.size
  break world
`;

Deno.test("an own parameter is updated in place and its result is the caller's to update", async () => {
  await compileAndRun(`${declarations}
func early (rows: own Array U32) -> (n: U32): Array U32 => return do:
  if n == 0:
    return rows
  rows[0] := n
  break rows
func forward (rows: own Array U32) -> (n: U32): Array U32 => return do:
  rows[1] := n
  break fill rows n
func total (rows: own Array U32): U32 => return rows[0] + rows[1]
entry func rebound (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0, 0], size: 3 }
  world := damage world 1
  for i in 0..n:
    world := damage world 2
  world.counts[0] := world.size
  break world.counts[0] * 100 + world.counts[1] * 10 + world.counts[2]
entry func fresh (n: U32) : U32 => return do:
  let rows = fill #[1, 2, 3] n
  rows[0] := 1
  break rows[0] + rows[1] + rows[2]
entry func copied (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  let after = fill rows.copy n
  break rows[0] * 100 + after[0]
entry func arms (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let result = 0
  if n == 0:
    let same = early rows n
    result := same[0]
  else:
    let changed = forward rows n
    result := changed[0] + changed[1]
  break result
entry func each_iteration (n: U32) : U32 => return do:
  let sum = 0
  for i in 0..n:
    let rows = #[i, i]
    sum := sum + total rows
  break sum
entry func dotted (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 1 }
  for i in 0..n:
    world := world.grow 2
  let grown = World.grow world 10
  grown.counts[1] := 5
  break grown.size * 100 + grown.counts[0] * 10 + grown.counts[1]
entry func scalar (n: U32) : U32 => return do:
  let rows = #[n, 2]
  let read = rows[0]
  let after = fill rows 4
  break read * 10 + after[1]
`, (guest) => {
    equal(guest.call("rebound", 4), 314);
    equal(guest.call("fresh", 5), 11);
    equal(guest.call("copied", 7), 107);
    equal(guest.call("arms", 0), 1);
    equal(guest.call("arms", 6), 12);
    equal(guest.call("each_iteration", 4), 12);
    equal(guest.call("scalar", 3), 34);
    equal(guest.call("dotted", 2), 1655);
  });
});

const spent = "This name was passed to an `own` parameter, so its value now belongs to that call; use the call's result, or pass values.copy there to keep this one";
const argument = "An `own` parameter takes a value that nothing else holds: a fresh value, or a local that alone holds it and, inside a loop, was bound in the same iteration; pass values.copy of it otherwise";
const result = "A function's result belongs to its caller alone, so it must be a fresh value or a local that alone holds its value; return values.copy of it, or take the parameter it comes from with `own`";
const value = "A function that takes over a parameter must be given all its arguments in one call; given only some, it would hold that value for any number of calls";
const position = "`own` marks a parameter of a function or a lambda, the parameter of a function type, or an argument given away at a call; it is not a name, a contract member, an implementation member and a member an operator stands for cannot take one yet, and no other type can be `own`";

// Each case: the code, its message, the source and the text the diagnostic
// points at, marked with « and »; a case without marks is about a whole
// declaration.

Deno.test("a lambda and a function value take a parameter over, in a type that says so", async () => {
  await compileAndRun(`${declarations}
func through (step: own Array U32 -> U32 -> Array U32) -> (n: U32): Array U32 => return do:
  let rows = #[n, 2]
  rows := step rows 5
  rows[0] := self + 1
  break rows
type Hooks is data = $Hooks { step: own World -> U32 -> World, scale: U32 }
func each (hooks: Hooks) -> (world: own World): World => return do:
  for index in 0..world.size:
    world := hooks.step world index
  break world
entry func lambda (n: U32) : U32 => return do:
  let rows = through (func (rows: own Array U32) -> (k: U32) => return do:
    rows[1] := k
    break rows) n
  break rows[0] * 10 + rows[1]
entry func inferred (n: U32) : U32 => return do:
  let rows = through (func rows -> k => return do:
    rows[1] := k + 1
    break rows) n
  break rows[0] * 10 + rows[1]
entry func named (n: U32) : U32 => return do:
  let rows = through fill n
  break rows[0] * 10 + rows[1]
entry func stored (n: U32) : U32 => return do:
  let hooks = $Hooks { step: damage, scale: n }
  let world = each hooks ($World { counts: #[0, 0, 0], size: 3 })
  world.counts[0] := self + hooks.scale
  break world.counts[0] * 100 + world.counts[1] * 10 + world.counts[2]
`, (guest) => {
    equal(guest.call("lambda", 4), 55);
    equal(guest.call("inferred", 4), 56);
    equal(guest.call("named", 4), 65);
    equal(guest.call("stored", 7), 811);
  });
});

Deno.test("generic code gives a value away with own at the call, and takes one by (own name)", async () => {
  await compileAndRun(`${declarations}
func twice step -> (own state) => return do:
  state := step (own state) 1
  state := step own state 2
  break state
func settle (own access) => return do:
  access.counts[0] := access.size
  break access
entry func named (n: U32) : U32 => return do:
  let rows = twice fill #[n, 9]
  break rows[0] * 10 + rows[1]
entry func lambda (n: U32) : U32 => return do:
  let rows = twice (func rows -> k => return do:
    rows[1] := rows[1] + k
    break rows) #[n, 2]
  break rows[0] * 10 + rows[1]
entry func untyped (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: n }
  world := settle world
  break world.counts[0]
`, (guest) => {
    equal(guest.call("named", 4), 22);
    equal(guest.call("lambda", 4), 45);
    equal(guest.call("untyped", 7), 7);
  });
  const lent = `${declarations}
func read (rows: Array U32) -> (k: U32): U32 => return rows[k]
entry func run (n: U32) : U32 => return do:
  let rows = #[n, 2]
  break read (own rows) 1
`;
  await compileExpectedFailure(lent, "type_mismatch");
});
// A field of a local that alone holds its value can be given to an `own`
// parameter. It is spent until something is put back in it; the other
// fields, and an argument that is only lent in the same call, stay their
// holder's own.
Deno.test("a field is given to an own parameter and put back", async () => {
  await compileAndRun(`${declarations}
type Pair is data = $Pair { left: Array U32, right: Array U32 }
func copied (from: Array U32) -> (rows: own Array U32): Array U32 => return do:
  rows[0] := from[0]
  break rows
entry func put_back (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  world.counts := fill world.counts n
  world := damage world 1
  break world.counts[0] * 10 + world.counts[1]
entry func later (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: n }
  let filled = fill world.counts 3
  let size = world.size
  world.counts := filled
  break world.counts[1] * 10 + size
entry func rounds (n: U32) : U32 => return do:
  let pair = $Pair { left: #[1, 1], right: #[5, 5] }
  for i in 0 .. n:
    pair.left := fill pair.left (pair.right[0] + i)
    pair.right := copied pair.left pair.right
  break pair.left[1] * 100 + pair.right[0]
entry func lent_beside (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  let seen = #[n, 9]
  world.counts := copied seen world.counts
  seen[0] := 4
  break world.counts[0] * 10 + seen[0]
`, (guest) => {
    equal(guest.call("put_back", 4), 45);
    equal(guest.call("later", 6), 36);
    equal(guest.call("rounds", 3), 808);
    equal(guest.call("lent_beside", 7), 74);
  });
});

// A record too wide for registers is a block of memory. Handing it round a
// loop, updating through it and returning it beside another value must not
// use a new block each time: 300,000 rounds of 288 bytes would not fit the
// stack.
Deno.test("a wide record handed round a loop is not copied onto the stack each round", async () => {
  await compileAndRun(`type Wide = {f0: Array U32, f1: Array U32, f2: Array U32, f3: Array U32, f4: Array U32, f5: Array U32, f6: Array U32, f7: Array U32, f8: Array U32, f9: Array U32, f10: Array U32, f11: Array U32, f12: Array U32, f13: Array U32, f14: Array U32, f15: Array U32, f16: Array U32, f17: Array U32, f18: Array U32, f19: Array U32, f20: Array U32, f21: Array U32, f22: Array U32, f23: Array U32}
func wide (): Wide => return {f0: #[0], f1: #[0], f2: #[0], f3: #[0], f4: #[0], f5: #[0], f6: #[0], f7: #[0], f8: #[0], f9: #[0], f10: #[0], f11: #[0], f12: #[0], f13: #[0], f14: #[0], f15: #[0], f16: #[0], f17: #[0], f18: #[0], f19: #[0], f20: #[0], f21: #[0], f22: #[0], f23: #[0]}
func step (world: own Wide): Wide => return do:
  world.f0[0] := world.f0[0] + 1
  break world
func counted (world: own Wide) => return do:
  world := step world
  break (world.f0[0], world)
entry func updated (n: U32) : U32 => return do:
  let world = wide ()
  for 0 .. n:
    world.f1[0] := world.f1[0] + 2
  break world.f1[0]
entry func handed (n: U32) : U32 => return do:
  let world = wide ()
  for 0 .. n:
    world := step world
  break world.f0[0]
entry func paired (n: U32) : U32 => return do:
  let world = wide ()
  let seen = 0
  for 0 .. n:
    let (count, next) = counted world
    world := next
    seen := count
  break seen + world.f0[0]
`, (guest) => {
    equal(guest.call("updated", 300000), 600000);
    equal(guest.call("handed", 300000), 300000);
    equal(guest.call("paired", 300000), 600000);
  });
});

const rejected: [string, string, string, string][] = [
  ["a name read after it was given away", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let after = fill rows n
  break «rows»[0] + after[0]`],
  ["a name given away twice", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let one = fill rows n
  let two = fill «rows» n
  break one[0] + two[0]`],
  ["a name given away in one arm and read after both", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let seen = 0
  if n == 1:
    let after = fill rows n
    seen := after[0]
  break seen + «rows»[0]`],
  ["a name given away and read in a later argument", "spent_value", spent, `
func put (rows: own Array U32) -> (n: U32): Array U32 => return do:
  rows[0] := n
  break rows
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let after = put rows (first «rows»)
  break after[0]`],
  ["a closure that reads a name given away", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let after = fill rows n
  let read = func (i: U32) => return «rows»[i]
  break read 0 + after[0]`],
  ["an argument another name holds", "own_argument", argument, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let alias = rows
  let after = fill «rows» n
  break alias[0] + after[0]`],
  ["a borrowed parameter as the argument", "own_argument", argument, `
func lend (rows: Array U32) -> (n: U32): Array U32 => return fill «rows» n
entry func run (n: U32) : U32 => return (lend #[1, 2] n)[0]`],
  ["a local of an outer scope given away in a loop", "own_argument", argument, `
entry func run (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let sum = 0
  for i in 0..n:
    let after = fill «rows» i
    sum := sum + after[0]
  break sum`],
  ["a record that shares a field", "own_argument", argument, `
entry func run (n: U32) : U32 => return do:
  let counts = #[0, 0]
  let world = $World { counts: counts, size: 2 }
  let next = damage «world» 0
  break next.counts[0] + counts[0]`],
  ["a part of a local read after it was given", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  let after = fill world.counts n
  break after[0] + «world.counts»[1]`],
  ["a local read as a whole while a part of it is given", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  let after = fill world.counts n
  let next = damage «world» 0
  break after[0] + next.size`],
  ["a part lent and given in one call", "own_argument", argument, `
func mixed (seen: Array U32) -> (rows: own Array U32): Array U32 => return do:
  rows[0] := seen[1]
  break rows
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, n], size: 2 }
  world.counts := mixed world.counts «world.counts»
  break world.counts[0]`],
  ["a result that is a borrowed parameter", "result_not_owned", result, `
func pick (rows: own Array U32) -> (other: Array U32): Array U32 => return «other»
entry func run (n: U32) : U32 => return (pick #[1] #[n])[0]`],
  ["a result two fields share", "result_not_owned", result, `
func both (rows: own Array U32) => return do:
  let alias = rows
  break { left: «rows», right: alias }
entry func run (n: U32) : U32 => return (both #[n]).left[0]`],
  ["a value read after a function value took it over", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let apply = fill
  let rows = #[1, 2]
  let after = apply rows n
  break after[0] + «rows»[0]`],
  ["a lambda's own parameter given a borrowed value", "own_argument", argument, `
func through (step: own Array U32 -> Array U32) -> (rows: Array U32): U32 => return (step «rows»)[0]
entry func run (n: U32) : U32 => return through (func (rows: own Array U32) => return rows) #[n]`],
  ["an own function partly applied", "own_function_value", value, `
entry func run (n: U32) : U32 => return do:
  let with_rows = «fill #[1, 2]»
  break (with_rows n)[0]`],
  ["a value read after value.member gave it away", "spent_value", spent, `
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 1 }
  let grown = world.grow n
  break grown.size + «world.size»`],
  ["value.member of an own function used as a value", "own_function_value", value, `
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 1 }
  let grow = «world.grow»
  break (grow n).size`],
  ["own on a member an operator stands for", "own_parameter", position, `
func World.add (left: own World) -> (right: World): World => return do:
  left.size := left.size + right.size
  break left
entry func run (n: U32) : U32 => return do:
  let sum = $World { counts: #[0], size: n } + $World { counts: #[1], size: 2 }
  break sum.size`],
  ["own in a type that is not a function's parameter", "own_parameter", position, `
entry func run (n: U32) : U32 => return do:
  let rows: Array («own U32») = #[n]
  break rows[0]`],
  ["own as the name of a local", "own_parameter", position, `
entry func run (n: U32) : U32 => return do:
  let own = n
  break own`],
  ["own as the name of a parameter", "own_parameter", position, `
func twice own => return own + own
entry func run (n: U32) : U32 => return twice n`],
  ["own as the name of a constant", "own_parameter", position, `
const own = 3
entry func run (n: U32) : U32 => return n`],
];

Deno.test("own arguments, spent names, owned results and own positions are checked", async () => {
  for (const [name, code, message, body] of rejected) {
    const marked = `${declarations}${body}\n`;
    const start = marked.indexOf("«");
    const end = marked.indexOf("»") - 1;
    const source = marked.replace("«", "").replace("»", "");
    let span: [number, number] | undefined = [start, end];
    if (start < 0) span = undefined;
    try {
      await compileExpectedFailure(source, code, message, { span });
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});

async function project(files: Record<string, string>): Promise<{ success: boolean; records: Record<string, unknown>[]; bytes?: Uint8Array<ArrayBuffer> }> {
  await Deno.mkdir(buildDir, { recursive: true });
  const dir = await Deno.makeTempDir({ dir: buildDir, prefix: "own-parameter-project-" });
  try {
    for (const [name, text] of Object.entries(files)) await Deno.writeTextFile(`${dir}/${name}.blot`, text);
    const output = `${dir}/program.wasm`;
    const built = await new Deno.Command(compiler, {
      args: ["build-project", `${dir}/main.blot`, output, "--prelude", new URL("../../std/prelude.blot", import.meta.url).pathname],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const records = new TextDecoder().decode(built.stdout).trim().split("\n").map((line) => JSON.parse(line));
    if (!built.success) return { success: false, records };
    return { success: true, records, bytes: await Deno.readFile(output) };
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

const library = `type World is data = $World { counts: Array U32, size: U32 }
func damage (world: own World) -> (index: U32): World => return do:
  world.counts[index] := world.counts[index] + 1
  break world
func World.grow (world: own World) -> (amount: U32): World => return do:
  world.size := world.size + amount
  break world
`;

Deno.test("a call into another module gives its argument away", async () => {
  const built = await project({
    main: `import { damage, World } from "./worlds"
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  for i in 0..n:
    world := damage world 1
    world := world.grow 1
  world.counts[0] := 7
  break world.size * 100 + world.counts[0] * 10 + world.counts[1]
`,
    worlds: library,
  });
  if (!built.success || !built.bytes) throw new Error(JSON.stringify(built.records));
  const guest = await instantiateGuest(built.bytes);
  try {
    equal(guest.call("run", 3), 573);
  } finally {
    guest.dispose();
  }
});

Deno.test("a name given to another module's own parameter is spent", async () => {
  const main = `import { damage, World } from "./worlds"
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  let next = damage world 1
  break world.counts[1] + next.counts[1]
`;
  const built = await project({ main, worlds: library });
  equal(built.success, false);
  const diagnostic = built.records.find((record) => record.kind === "diagnostic");
  equal(diagnostic?.code, "spent_value");
  equal(diagnostic?.start, main.indexOf("world.counts[1] +"));
  // The diagnostic points at the dotted path the spent name starts.
  equal(diagnostic?.end, main.indexOf("world.counts[1] +") + "world.counts".length);
});

Deno.test("another module's own function is a value that takes its argument over", async () => {
  const built = await project({
    main: `import { damage, World } from "./worlds"
entry func run (n: U32) : U32 => return do:
  let step = damage
  let next = step ($World { counts: #[0, 0], size: 2 }) 1
  break next.counts[1]
`,
    worlds: library,
  });
  equal(built.success, true);
  const main = `import { damage, World } from "./worlds"
entry func run (n: U32) : U32 => return do:
  let step = damage
  let world = $World { counts: #[0, 0], size: 2 }
  let next = step world 1
  break world.size + next.size
`;
  const spent = await project({ main, worlds: library });
  equal(spent.success, false);
  const diagnostic = spent.records.find((record) => record.kind === "diagnostic");
  equal(diagnostic?.code, "spent_value");
  equal(diagnostic?.start, main.indexOf("world.size +"));
});

Deno.test("a value given to another module's member by value.member is spent", async () => {
  const main = `import { World } from "./worlds"
entry func run (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], size: 2 }
  let next = world.grow n
  break world.size + next.size
`;
  const built = await project({ main, worlds: library });
  equal(built.success, false);
  const diagnostic = built.records.find((record) => record.kind === "diagnostic");
  equal(diagnostic?.code, "spent_value");
  equal(diagnostic?.start, main.indexOf("world.size +"));
});
