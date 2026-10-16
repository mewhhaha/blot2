import { compileAndRun, equal } from "./compile_helpers.ts";

const declarations = `type Identity = forall [a] => a -> a
const identity: Identity = fn value => value
type Point is data = #Point { x: U32 }
const Point.add = fn (left: Point) => fn (right: U32) => @u32.add left.x right
const combine = fn left => fn right => @type.call "add" left right
const represented: a -> a where { type_rep a } = fn value => value
const field = fn value => value.x
const forward = fn value => combine value 22
`;

Deno.test("ordinary constrained helpers execute beside universal values", async () => {
  await compileAndRun(
    declarations +
      `entry const answer = fn (value: U32) => identity (forward (#Point { x: represented (field {x: value}) }))
entry const named = fn (value: U32) => field (#Point {x: value})
entry const fraction = fn (value: F32) => represented (field {x: value})
`,
    (guest) => {
      for (let value = 0; value < 96; value++) {
        equal(guest.call("answer", value), value + 22);
        equal(guest.call("named", value), value);
        equal(guest.call("fraction", value + 0.5), value + 0.5);
      }
      const warmed = guest.memoryBytes();
      for (let value = 0; value < 96; value++) {
        equal(guest.call("answer", value), value + 22);
      }
      equal(guest.memoryBytes(), warmed);
    },
    { prelude: "none" },
  );
});

Deno.test("ordinary associated helpers retry a compatible right owner beside forall", async () => {
  await compileAndRun(
    `const identity: forall [a] => a -> a = fn value => value
type Left is data = #Left {value: U32}
type Right is data = #Right {value: U32}
const Left.add = fn (left: Left) => fn (right: U32) => @u32.add left.value right
const Right.add = fn (left: Left) => fn (right: Right) => @u32.add left.value right.value
const combine = fn left => fn right => @type.call "add" left right
entry const answer = fn (value: U32) => identity (combine (#Left {value: value}) (#Right {value: 22}))
`,
    (guest) => equal(guest.call("answer", 20), 42),
    { prelude: "none" },
  );
});
