import { ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { equal } from "./compile_helpers.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

// A static nominal value stores a pure checkpoint callback; a generic lambda
// captures it where the checked type widened that row to State operations.
// The evaluator reopens stored callback rows before fixing the nominal
// argument, as the checker does at each use.
const ecs = "import * as array from \"std/array\"\n\ntype Builder [world, scope, checkpoint, schema] is data = #Builder { initial: world, scope: world -> scope, checkpoint: checkpoint, schema: schema }\ntype Simulation [world, scope, checkpoint] is data = #Simulation { initial: world, scope: world -> scope, checkpoint: checkpoint }\ntype End is data = #End\ntype Entry { head, tail } is data = #Entry { head, tail }\ntype Column component is data = #Column (Array (Maybe component))\ntype Snapshot value is data = #Snapshot value\ntype Entities is data = #Entities (Array Bool)\ntype Entity is data = #Entity (Maybe U32)\n\ntype State a is effect = {\n  get: Unit -> a\n  set: a -> Unit\n}\n\nconst End.contains = func (end: End) => return func witness => return false\n\nconst Entry.contains = func entry => return func witness => return do:\n  let #Entry { head, tail } = entry\n  if :head == :witness:\n    break true\n  break tail.contains(witness)\n\nconst get = func (witness: p -> a) : a => return State.get ()\nconst set = func value => return State.set value\n\n// Builders are rebuilt field by field: a path update such as\n// `builder.initial := (value, self)` changes the builder's type, and blotc\n// crashes when such a generic helper is applied twice.\nconst empty = func () => return do:\n  let scope = func world => return func action => return do:\n    use result <- action ()\n    break (world, result)\n  break #Builder { initial: (), scope, checkpoint: func () => return (), schema: #End }\n\nconst insert_cell = func initial => return func builder => return do:\n  let #Builder { initial: previous_initial, scope: previous_scope, checkpoint, schema } = builder\n  let scope = func world => return func action => return do:\n    let (current, previous) = world\n    use outcome <- @effect.run State.get State.set current (func () => return previous_scope previous action)\n    let (next, (previous_next, result)) = outcome\n    break ((next, previous_next), result)\n  break #Builder { initial: (initial, previous_initial), scope, checkpoint, schema }\n\nconst insert_snapshotted = func initial => return func builder => return do:\n  let #Builder { checkpoint: previous_checkpoint } = builder\n  builder := insert_cell initial self\n  builder := insert_cell (#Snapshot initial) self\n  let #Builder { initial: initial_world, scope, schema } = builder\n  let checkpoint = func () => return do:\n    use previous_checkpoint ()\n    use current <- get (func () => return initial)\n    use set (#Snapshot current)\n  break #Builder { initial: initial_world, scope, checkpoint, schema }\n\nconst insert_resource = func value => return func builder => return do:\n  let #Builder { schema } = builder\n  if schema.contains(value):\n    break @panic \"resource type already initialized\"\n  let #Builder { initial, scope, checkpoint } = insert_cell value builder\n  break #Builder { initial, scope, checkpoint, schema: #Entry { head: value, tail: schema } }\n\n// Snapshotted resources and components also keep their value from the last\n// checkpoint, readable through `previous` and `previous_components`.\nconst insert_snapshotted_resource = func value => return func builder => return do:\n  let #Builder { schema } = builder\n  if schema.contains(value):\n    break @panic \"resource type already initialized\"\n  let #Builder { initial, scope, checkpoint } = insert_snapshotted value builder\n  break #Builder { initial, scope, checkpoint, schema: #Entry { head: value, tail: schema } }\n\nconst new = func () => return do:\n  let builder = empty ()\n  builder := insert_cell (#Entities #[]) self\n  builder := insert_cell (#Entity #Nothing) self\n  break builder\n\nconst build = func builder => return do:\n  let #Builder { initial, scope, checkpoint } = builder\n  break #Simulation { initial, scope, checkpoint }\n\nconst run = func simulation => return func world => return func action => return do:\n  let #Simulation { scope } = simulation\n  break scope world action\n\nconst create = func simulation => return func action => return do:\n  let #Simulation { initial } = simulation\n  break run simulation initial action\n\nconst checkpoint = func simulation => return do:\n  let #Simulation { checkpoint } = simulation\n  break checkpoint ()\n";
const entry = "import * as ecs from \"./ecs\"\ntype Clock is data = #Clock { tick: U32, remainder: F32 }\nconst advance = func checkpoint => return func (n: F32) => return do:\n  use checkpoint ()\n  break ()\nconst engine = ecs.build (ecs.insert_resource #Clock { tick: 0, remainder: 0.0 } (ecs.new ()))\n\nconst scoped = func engine => return func (delta: F32) => return do:\n  use advance (func () => return ecs.checkpoint engine) delta\n  break ()\nentry const main = func (x: F32) => return do:\n  let (_, r) = ecs.create engine (func () => return scoped engine x)\n  break x\n";

Deno.test("static captures widen stored callback rows inside nominal arguments", async () => {
  const directory = await Deno.makeTempDir();
  const main = `${directory}/main.blot`;
  const prelude = new URL("../../std/prelude.blot", import.meta.url);
  const stdRoot = new URL("../../std", import.meta.url);
  const compiler = await createZigProjectCompiler({ executable, entry: main, prelude, stdRoot });
  try {
    const built = await compiler.build({ sources: { [main]: entry, [`${directory}/ecs.blot`]: ecs } });
    ok(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    try {
      equal(guest.call("main", 2.5), 2.5);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
