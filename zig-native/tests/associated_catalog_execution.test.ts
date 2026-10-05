import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("primitive associated selection depends on the actual prelude catalog", async () => {
  for (const source of [
    'entry const answer=fn()=>@type.call "add" 21 21\n',
    'entry const folded=@type.call "add" 21 21\n',
    'const U32.add=fn left=>fn right=>@u32.add left right\nentry const answer=fn()=>@type.call "add" 21 21\n',
    'const U32.add=fn left=>fn right=>99\nentry const answer=fn()=>@type.call "add" 21 21\n',
  ]) {
    await compileExpectedFailure(source, "missing_associated", undefined, { prelude: "none" });
    await compileAndRun(source, guest => {
      if (source.includes("entry const folded")) equal(guest.read("folded"), 42);
      else for (let i=0;i<100;i++) equal(guest.call("answer",null),42);
    }, { prelude: "std/prelude.blot" });
  }
  for (const prelude of ["none", "std/prelude.blot"])
    await compileExpectedFailure('entry const answer=fn()=>@type.call "eq" #True #True\n', "missing_associated", undefined, { prelude });
});

Deno.test("ordinary primitive names keep lexical meaning while nominal methods enter their type catalog", async () => {
  await compileAndRun('const U32.add=fn left=>fn right=>@u32.add left right\nentry const answer=fn()=>U32.add 21 21\nentry const folded=answer ()\n', guest => {
    equal(guest.read("folded"),42);
    for(let i=0;i<100;i++) equal(guest.call("answer",null),42);
  }, { prelude: "none" });
  await compileAndRun(`type Box is data=#Box U32
const Box.add=fn left=>fn right=>do:
  let #Box a=left
  let #Box b=right
  return #Box (@u32.add a b)
entry const answer=fn()=>case @type.call "add" (#Box 21) (#Box 21) of
  #Box value=>value
entry const folded=answer ()
`, guest => {
    equal(guest.read("folded"),42);
    for(let i=0;i<100;i++)equal(guest.call("answer",null),42);
  }, { prelude: "none" });
});
