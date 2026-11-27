import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const catalogSources = [
  'io const answer=func(): U32 => return @type.call "add" 21 21\n',
  'io const folded: U32=@type.call "add" 21 21\n',
  'const U32.add=func left=> return func right=> return @u32.add left right\nio const answer=func(): U32 => return @type.call "add" 21 21\n',
  'const U32.add=func left=> return func right=> return 99\nio const answer=func(): U32 => return @type.call "add" 21 21\n',
];

Deno.test("primitive associated selection fails without a prelude catalog", async () => {
  for (const source of catalogSources) {
    await compileExpectedFailure(source, "missing_associated", undefined, {
      prelude: "none",
    });
  }
  await compileExpectedFailure(
    'io const answer=func(): Bool => return @type.call "eq" true true\n',
    "missing_associated",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("primitive associated selection uses the actual prelude catalog", async () => {
  for (const source of catalogSources) {
    await compileAndRun(source, (guest) => {
      if (source.includes("io const folded")) {
        equal(guest.read("folded"), 42);
      } else {for (let i = 0; i < 100; i++) {
          equal(guest.call("answer", null), 42);
        }}
    }, { prelude: "std/prelude.sq" });
  }
  await compileAndRun(
    'io const answer=func(): Bool => return @type.call "eq" true true\n',
    (guest) => {
      equal(guest.call("answer", null), true);
    },
    { prelude: "std/prelude.sq" },
  );
});

Deno.test("ordinary primitive names keep lexical meaning while nominal methods enter their type catalog", async () => {
  await compileAndRun(
    "const U32.add=func left=> return func right=> return @u32.add left right\nio const answer=func()=> return U32.add 21 21\nio const folded=answer ()\n",
    (guest) => {
      equal(guest.read("folded"), 42);
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
    },
    { prelude: "none" },
  );
  await compileAndRun(
    `type Box is data= $Box U32
const Box.add=func left=> return func right=> return do:
  let $Box a=left
  let $Box b=right
  break $Box (@u32.add a b)
io const answer=func()=> return case @type.call "add" ($Box 21) ($Box 21) of
  $Box value=>value
io const folded=answer ()
`,
    (guest) => {
      equal(guest.read("folded"), 42);
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
    },
    { prelude: "none" },
  );
});
