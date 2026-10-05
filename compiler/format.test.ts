import { deepStrictEqual as equal } from "node:assert/strict";
import { formatSource } from "./format.ts";

Deno.test("formatter preserves comments, literals, postfix calls, selectors and layout", async () => {
  const source = `// leading comment
import * as array from "std/array"

type Point is data =
  | #Point {x:U32,y:U32}
const from = fn value=>value
entry const answer=fn ()=>do:
  let point=#Point {x: 1,y:2} // keep this
  let values = array.map (.x) #[point]
  let choose = if :point==:(#Point {x:2,y:3}) then 40 else 0
  return values[0]+choose + from (-1.0)
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r")), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("values[0] + choose"), true);
  equal(formatted.includes("array.map .x #[point]"), true);
  equal(formatted.includes("  // keep this"), true);
  equal(formatted.includes("if :point == :#Point"), true);
});

Deno.test("formatter separates variants and preserves arithmetic and call grouping", async () => {
  const source =
    `type Drag is data = #Idle | #Draw { x: F32, y: F32, width: F32, height: F32 } | #Move { x: F32, y: F32 }
const apply = fn f => fn value => f value
entry const answer = fn x => do:
    let total = (1 + 2) * x
    let value = apply (fn value => value) (total + 1)
    return ((value))
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("type Drag is data =\n  | #Idle\n  | #Draw"), true);
  equal(formatted.includes("(1 + 2) * x"), true);
  equal(formatted.includes("(total + 1)"), true);
  equal(formatted.includes("return value"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves collection kind spread comprehension and tag boundaries", async () => {
  const source = `@[identity]
const list=[1, 2]
const array=#[1, 2]
const front=[0,...list]
const back=#[...array,3]
const mapped=#[x+1 | x <- list, x>0, let y=x*2]
const get=fn xs=>xs[0]
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("const list = [1, 2]"), true);
  equal(formatted.includes("const array = #[1, 2]"), true);
  equal(formatted.includes("[0, ...list]"), true);
  equal(formatted.includes("#[...array, 3]"), true);
  equal(formatted.startsWith("@[identity]\n"), true);
  equal(formatted.includes("xs[0]"), true);
});
