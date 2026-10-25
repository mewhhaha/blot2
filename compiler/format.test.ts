import { deepStrictEqual as equal } from "node:assert/strict";
import { formatSource } from "./format.ts";

Deno.test("formatter preserves spark and receive boundaries", async () => {
  const source = `entry const sparked = fn () => @task.scope (fn group => do:
  let pending = *(work 42)
  return |pending|)
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("@task.scope (fn group => do:"), true);
  equal(formatted.includes("*(work 42)"), true);
  equal(formatted.includes("|pending|"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves grouped curried parameter lists and named record calls", async () => {
  const source = `const area=fn (width:U32) (height:U32)=>@u32.mul width height
const named=fn (fields:{width:U32,height:U32})=>area fields.width fields.height
entry const answer=fn ()=>named {height:3,width:4}
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("fn (width: U32) (height: U32) =>"), true);
  equal(formatted.includes("named { height: 3, width: 4 }"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves continue and a flat pattern guard", async () => {
  const source = `type Candidate is data=#Keep U32|#Skip
entry const kept=fn (values:Array Candidate)=>do:
  let total=0
  for candidate in values:
    let #Keep value=candidate else:
      continue
    total:=self+value
  break total
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("      continue"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves typed code descriptors and stage composition", async () => {
  const source = `const code=1
const descriptor=fn code=>code
const left:code [U32,row {}]=@code.quote 40
const shape:descriptor (code [U32,row {Foreign}])=@code.describe left
const answer=@code.quote (@u32.add (@code.splice left) (@code.lift 2))
entry const run=fn ()=>@code.emit answer
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("code [U32, row {}]"), true);
  equal(formatted.includes("descriptor (code [U32, row { Foreign }])"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves erased proof annotations and exact operand grouping", async () => {
  const source =
    `const at:(values:Array a)->(index:U32)->(@proof.Index values index)->a=fn values=>fn index=>fn proof=>@array.get values index
const less:(values:List U32)->@proof.U32Lt (0) (@list.length values)=fn values=>@proof.lt 0 (@list.length values)
const last:@proof.U32Le 0 4294967295=@proof.le 0 4294967295
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("@proof.Index values index"), true);
  equal(formatted.includes("(@list.length values)"), true);
  equal(formatted.includes("4294967295"), true);
});

Deno.test("formatter preserves dependent arrow binders and staged row grouping", async () => {
  const source = `type State a is effect={get:Unit->a,set:a->Unit}
const read:(state:State a)->a!{state.get}=fn input=>input.get ()
const apply:(state:State a)->((Unit->a!{state.get|e})->a!{state.get|e})=fn input=>fn callback=>callback ()
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("(state: State a)"), true);
  equal(formatted.includes("((Unit -> a ! { state.get | e })"), true);
});

Deno.test("formatter preserves private opaque forwarding and constructor lambda syntax", async () => {
  const source = `export {Token as Ticket, make} from "./tokens"
private opaque type Token=F32
opaque type Box a={value:a}
private type Alias=U32
private type Choice is data=#Choice U32
private type Read a is contract={type_rep a}
private effect Hidden:Unit->U32
private type HiddenFamily is effect={ask:Unit->U32}
private const private=fn opaque=>opaque
private entry const answer=fn export=>private export
const unwrap=fn (#Box value)=>value.value
const typed=fn (value:U32)=>value
const pattern=fn ((left,right))=>left
export {Box} from "./tokens"
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("private opaque type Token = F32"), true);
  equal(formatted.includes("fn (#Box value)"), true);
  equal(formatted.includes("fn ((left, right))"), true);
  equal(
    formatted.includes('export { Token as Ticket, make } from "./tokens"'),
    true,
  );
});

Deno.test({
  name: "formatter keeps source and forwarded opaque project Wasm identical",
  ignore: Deno.args[0] === undefined,
  async fn() {
    const { createZigProjectCompiler } = await import(
      "./zig_project_client.ts"
    );
    const directory = await Deno.makeTempDir({
      prefix: "blot-format-opacity-",
    });
    try {
      const entry = `${directory}/main.blot`;
      const sources = {
        [entry]:
          'import {make} from "./tokens"\nimport * as facade from "./facade"\ntype Alias=facade.Ticket\nentry const answer=fn (value:F32)=>facade.read (make value)\nentry const folded=facade.read (make 40.0)\n',
        [`${directory}/tokens.blot`]:
          "opaque type Token=F32\nprivate const offset=2.0\nconst make:F32->Token=fn value=>#Token (@f32.add value offset)\nconst read:Token->F32=fn (#Token value)=>value\nprivate const Token.hidden=read\n",
        [`${directory}/facade.blot`]:
          'export {Token as Ticket,read} from "./tokens"\n',
      };
      const formatted: Record<string, string> = {};
      for (const [path, source] of Object.entries(sources)) {
        await Deno.writeTextFile(path, source);
        formatted[path] = await formatSource(source);
        equal(await formatSource(formatted[path]), formatted[path]);
      }
      const options = {
        executable: Deno.args[0],
        entry,
        prelude: null,
        cacheDirectory: false as const,
      };
      const original = await createZigProjectCompiler(options);
      const rewritten = await createZigProjectCompiler(options);
      try {
        const expected = await original.build();
        const actual = await rewritten.build({ sources: formatted });
        equal(expected.success, true, JSON.stringify(expected));
        equal(actual.success, true, JSON.stringify(actual));
        if (expected.success && actual.success) {
          equal(actual.bytes, expected.bytes);
        }
      } finally {
        await original.dispose();
        await rewritten.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  },
});

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
  break values[0]+choose + from (-1.0)
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
    break ((value))
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("type Drag is data =\n  | #Idle\n  | #Draw"), true);
  equal(formatted.includes("(1 + 2) * x"), true);
  equal(formatted.includes("(total + 1)"), true);
  equal(formatted.includes("break value"), true);
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

Deno.test("formatter preserves aliases, named contracts, qualified predicates and typed holes", async () => {
  const source = `import * as contracts from "./contracts"
type Action a=Unit->a ! {|e}
type Add a is contract = {
  associated "add" a a a,
  contracts.Read a,
}
const contract=fn contract=>contract
const twice:a->a where {Add a}=fn value=>value+value
const convert:a->b ! {|e} where {result "from" a b ! {|e}}=fn value=>@type.result "from" value
const unfinished=fn (action:Action U32)=>@hole
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("type Add a is contract"), true);
  equal(formatted.includes("contracts.Read a"), true);
  equal(formatted.includes('result "from" a b'), true);
  equal(formatted.includes("@hole"), true);
});

Deno.test("formatter preserves structural record applications, patterns and merge contracts", async () => {
  const source = `type Point={x:U32,y:F32}
type Merge [a,b,c] is contract={merge a b c}
const combine:a->b->c where {Merge [a,b,c]}=fn left=>fn right=>@record.merge left right
const f=fn (point:Point)=>do:
    let {y,x}=point
    break combine point {x:y}
const value=f {y:2.0,x:40}
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("@record.merge left right"), true);
  equal(formatted.includes("combine point { x: y }"), true);
});

Deno.test("formatter accepts nominal record patterns and spaces named operators", async () => {
  const source = `type Vec2 is data = #Vec2 { x: F32, y: F32 }
const plus=fn left=>fn right=>left+right
const length=fn value=>do:
    let #Vec2 {x,y:height}=value
    break x+height
const first=fn value=>case value of
    #Some (#Vec2 {x}) => x
    _ => 0.0
const sum=fn ()=>20 \`plus\` 22
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("let #Vec2 { x, y: height } = value"), true);
  equal(formatted.includes("#Some (#Vec2 { x }) => x"), true);
  equal(formatted.includes("20 `plus` 22"), true);
});

// Every public example and std module formats idempotently, and the formatted
// sources compile to the same Wasm as the originals.
Deno.test("formatter keeps public examples and std modules compiling to identical Wasm", async () => {
  const executable = Deno.args[0];
  const repo = new URL("../", import.meta.url).pathname;
  const formatted: Record<string, string> = {};
  const examples: string[] = [];
  for (const directory of ["examples", "std"]) {
    for await (const entry of Deno.readDir(`${repo}${directory}`)) {
      if (!entry.isFile || !entry.name.endsWith(".blot")) continue;
      const path = `${repo}${directory}/${entry.name}`;
      const once = await formatSource(await Deno.readTextFile(path));
      equal(await formatSource(once), once, path);
      formatted[path] = once;
      if (directory === "examples") examples.push(path);
    }
  }
  if (!executable) return;
  const { createZigProjectCompiler } = await import(
    "./zig_project_client.ts"
  );
  const prelude = `${repo}std/prelude.blot`;
  const stdRoot = `${repo}std`;
  for (const entry of examples.sort()) {
    const options = {
      executable,
      entry,
      prelude,
      stdRoot,
      cacheDirectory: false as const,
    };
    const original = await createZigProjectCompiler(options);
    const rewritten = await createZigProjectCompiler(options);
    try {
      const expected = await original.build();
      const actual = await rewritten.build({ sources: formatted });
      equal(actual.success, expected.success, entry);
      if (actual.success && expected.success) {
        equal(actual.bytes, expected.bytes, entry);
      }
    } finally {
      await original.dispose();
      await rewritten.dispose();
    }
  }
});

Deno.test("formatter preserves associated equations abstract signatures and projection rows", async () => {
  const source = `type Identity a is contract={type Item=a}
type Source s is contract={type Item,const first:s->(Source.Item s)}
const keep:a->(Identity.Item a) where{Identity a,type_eq (Identity.Item a) a}=fn value=>value
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("type Item = a"), true);
  equal(formatted.includes("const first: s -> (Source.Item s)"), true);
  equal(formatted.includes("type_eq (Identity.Item a) a"), true);
});

Deno.test("formatter preserves implementation heads requirements and ordinary lambda members", async () => {
  const source =
    `type Source s is contract={type Item,const first:s->(Source.Item s)}
private impl ArraySource a:Source (Array a) where{type_eq a U32}={type Item=a,const first=fn values=>@array.get values 0}
const impl=fn impl=>impl
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(
    formatted.includes("private impl ArraySource a: Source (Array a)"),
    true,
  );
  equal(formatted.includes("type Item = a"), true);
  equal(
    formatted.includes("const first = fn values => @array.get values 0"),
    true,
  );
  equal(formatted.includes("const impl = fn impl => impl"), true);
});

Deno.test("formatter preserves usage qualifiers and contextual value names", async () => {
  const source = `const unique=1
const f:once (borrow r U32->shared U32)=fn x=>x
const g:cleanup (unique U32->Unit)=fn x=>()
const h:borrow_mut r [U32]=unique
const i:many (U32->U32)=fn x=>x
const j:concurrent (U32->U32 ! {Foreign})=host
const concurrent=1
const share=@usage.share unique
const scope=@resource.scope acquire release (fn resource=>resource)
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("once (borrow r U32 -> shared U32)"), true);
  equal(formatted.includes("borrow_mut r [U32]"), true);
});

Deno.test("formatter preserves quantified binders and package opening scope", async () => {
  const source = `const forall=fn pack=>pack
 type Id=forall [a]=>a->a
 type Borrower=forall [a,row e,region r]=>borrow r a->a!{|e}
 type Item=exists [a] where {Render a}=>a
 const make=pack [U32] 42 as Item
 const read=fn item=>unpack item as [a] value in Render.show value
 const plain=fn unpack=>unpack 1
`.replaceAll("\n ", "\n");
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("forall [a, row e, region r]"), true);
  equal(
    formatted.includes("unpack item as [a] value in Render.show value"),
    true,
  );
});
