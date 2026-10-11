import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const count = `const count = fn xs => do:
  let n = 0
  for x in xs:
    n := self + 1
  return n
`;

Deno.test("generic array iteration represents empty elements and unused data parameters", async () => {
  await compileAndRun(
    count + "entry const create = fn () => count #[]\n",
    (guest) => {
      equal(guest.call("create", null), 0);
    },
  );
  await compileAndRun(
    count + `type Box [a, b] is data = #A a | #B b
entry const create = fn () => count #[] + count #[#A 1, #A 2] * 10
entry const mixed = fn () => count #[#A 1, #B #True]
`,
    (guest) => {
      equal(guest.call("create", null), 20);
      equal(guest.call("mixed", null), 2);
    },
  );
});

Deno.test("generic cursors reconcile nested callback shapes across staged builders", async () => {
  await compileAndRun(
    `type System [start, event, update, render] is data = #Start start | #Event event | #Update update | #Render render
type Builder system is data = #Builder (Array system)
const add = fn stage => fn action => fn builder => do:
  let #Builder systems = builder
  return #Builder #[...systems, stage action]
const build = fn builder => do:
  let #Builder systems = builder
  let n = 0
  for system in systems:
    case system of
      #Start run => run ()
      #Update run => run 1.0
      #Render run => do:
        let ignored = run () 1.0
        return ()
      _ => ()
    n := self + 1
  return n
entry const create = fn () => do:
  let builder = #Builder #[]
  builder := add #Event (fn (event: U32) => ()) self
  builder := add #Start (fn () => ()) self
  return build builder
`,
    (guest) => {
      equal(guest.call("create", null), 2);
    },
  );
});

Deno.test("partial collection shapes preserve generic reuse and unresolved dispatch diagnostics", async () => {
  await compileAndRun(
    count + `const empty = #[]
const nothing = #Nothing
const result = fn candidate => Result.unwrap_or 0 candidate
entry const create = fn () => count #[...empty, 1] + count #[...empty, 2.0] * 10
entry const maybe = fn () => Maybe.unwrap_or 40 nothing + Maybe.unwrap_or 2 (#Some 2)
entry const ok = fn () => result (#Ok 42)
entry const error = fn () => result (#Err #False)
`,
    (guest) => {
      equal(guest.call("create", null), 11);
      equal(guest.call("maybe", null), 42);
      equal(guest.call("ok", null), 42);
      equal(guest.call("error", null), 0);
    },
  );
  await compileExpectedFailure(
    "entry const answer = fn () => from 1\n",
    "unresolved_type",
  );
});

Deno.test("partial collection shapes preserve fresh and retained output through concrete edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    for (
      const [elements, expected] of [["", 0], ["1, 2", 2], ["1.0", 1], [
        "",
        0,
      ]] as const
    ) {
      const sources = {
        [entry]: count + `entry const create = fn () => count #[${elements}]\n`,
      };
      const built = await compiler.build({ sources });
      ok(built.success, JSON.stringify(built));
      const fresh = await createZigProjectCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        ok(rebuilt.success, JSON.stringify(rebuilt));
        equal(built.bytes, rebuilt.bytes);
      } finally {
        await fresh.dispose();
      }
      const guest = await instantiateGuest(built.bytes);
      try {
        equal(guest.call("create", null), expected);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
