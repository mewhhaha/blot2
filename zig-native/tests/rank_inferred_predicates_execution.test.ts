import { compileAndRun, equal } from "./compile_helpers.ts";

const declarations = `type Identity = forall [a] => a -> a
const identity: Identity = func value => return value
type Point is data = #Point { x: U32 }
const Point.add = func (left: Point) => return func (right: U32) => return @u32.add left.x right
const combine = func left => return func right => return @type.call "add" left right
const represented: a -> a where { type_rep a } = func value => return value
const field = func value => return value.x
const forward = func value => return combine value 22
`;

Deno.test("ordinary constrained helpers execute beside universal values", async () => {
  await compileAndRun(
    declarations +
      `entry const answer = func (value: U32) => return identity (forward (#Point { x: represented (field {x: value}) }))
entry const named = func (value: U32) => return field (#Point {x: value})
entry const fraction = func (value: F32) => return represented (field {x: value})
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
    `const identity: forall [a] => a -> a = func value => return value
type Left is data = #Left {value: U32}
type Right is data = #Right {value: U32}
const Left.add = func (left: Left) => return func (right: U32) => return @u32.add left.value right
const Right.add = func (left: Left) => return func (right: Right) => return @u32.add left.value right.value
const combine = func left => return func right => return @type.call "add" left right
entry const answer = func (value: U32) => return identity (combine (#Left {value: value}) (#Right {value: 22}))
`,
    (guest) => equal(guest.call("answer", 20), 42),
    { prelude: "none" },
  );
});
