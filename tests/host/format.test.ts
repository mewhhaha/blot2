import { deepStrictEqual as equal } from "node:assert/strict";
import { formatSource } from "../../host/format.ts";

Deno.test("formatter preserves first-class test bodies and attributes", async () => {
  const source = `import * as test from "std/test"
const test=1
const expect_trap=2
test "basic math" :
  let x=2+2
  return x==4
test "shortcut"=>2+2==4
test expect_trap "div zero" :
  let _=1/0
test expect_trap "inline return"=>return 1/0
test expect_trap "arrow suite"=>
  let _=1/0
@[test.suite]
test "effectful" :
  use test.eq "ok" 4 (2+2)
@[test.suite]   test "inline tag":
  use test.holds "yes" true
`;
  const expected = `import * as test from "std/test"
const test = 1
const expect_trap = 2
test "basic math":
  let x = 2 + 2
  return x == 4
test "shortcut" => 2 + 2 == 4
test expect_trap "div zero":
  let _ = 1 / 0
test expect_trap "inline return" => return 1 / 0
test expect_trap "arrow suite" =>
  let _ = 1 / 0
@[test.suite]
test "effectful":
  use test.eq "ok" 4 (2 + 2)
@[test.suite] test "inline tag":
  use test.holds "yes" true
`;
  equal(await formatSource(source), expected);
  equal(await formatSource(expected), expected);
});

Deno.test("formatter preserves named private entry tagged and local curried functions", async () => {
  const source = `func add (left:U32)->(right:U32):U32=> return left+right
private func hidden_keep value=> return value
@[test]
func tagged ()=> return add 20 22
io answer ()=> do:
  func local (value:U32)->extra=> return add value extra
  let anonymous=func value=> return value
  return local (anonymous 40) 2
`;
  const formatted = await formatSource(source);
  equal(
    formatted.includes(
      "func add (left: U32) -> (right: U32): U32 => return left + right",
    ),
    true,
  );
  equal(
    formatted.includes("private func hidden_keep value => return value"),
    true,
  );
  equal(
    formatted.includes("@[test]\nfunc tagged () => return add 20 22"),
    true,
  );
  equal(formatted.includes("io answer () => do:"), true);
  equal(
    formatted.includes(
      "  func local (value: U32) -> extra => return add value extra",
    ),
    true,
  );
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
});

Deno.test("formatter preserves qualified function names and declaration constraints", async () => {
  const source = `func Vec3.add (left:Vec3)->(right:Vec3):Vec3=> return left
func eq (left:a)->(right:a):Bool where{Eq a}=> return Eq.eq left right
func keep value where{Eq a}=> return value
`;
  const formatted = await formatSource(source);
  equal(
    formatted.includes(
      "func Vec3.add (left: Vec3) -> (right: Vec3): Vec3 => return left",
    ),
    true,
  );
  equal(
    formatted.includes(
      "func eq (left: a) -> (right: a): Bool where { Eq a } => return Eq.eq left right",
    ),
    true,
  );
  equal(
    formatted.includes("func keep value where { Eq a } => return value"),
    true,
  );
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves spark and receive boundaries", async () => {
  const source =
    `io const sparked = func () => return @task.scope (func group => return do:
  let pending = *(work 42)
  return |pending|)
`;
  const formatted = await formatSource(source);
  equal(
    formatted.includes(
      "io const sparked = func () => return @task.scope (func group => return do:",
    ),
    true,
  );
  equal(formatted.includes("*(work 42)"), true);
  equal(formatted.includes("|pending|"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter keeps sparks and #kernel and #process declarations", async () => {
  const source = `func prep (w:Array F32):Array F32=> return w
func step_item (ctx:Array F32)->(x:U32):U32=> return x
func init_p (seed:U32):U32=> return seed
func step_p (st:own U32)->(cmd:U32):(U32,U32)=> return (st,cmd)
#kernel func mix (x:U32):U32=> return x
#kernel const plan:Kernel [Array F32,U32,U32]={prepare:prep,run:step_item}
#process const planner:Process [U32,U32,U32]={init:init_p,step:step_p}
io double(xs:Array U32):Array U32=> return spark #[@u32.add x x | x<-xs]
io indexed(n:U32):Array U32=> return spark #[x | x<-0..n]
`;
  const formatted = await formatSource(source);
  equal(
    formatted.includes("#kernel func mix (x: U32): U32 => return x"),
    true,
  );
  equal(
    formatted.includes(
      "#kernel const plan: Kernel [Array F32, U32, U32] = { prepare: prep, run: step_item }",
    ),
    true,
  );
  equal(
    formatted.includes(
      "#process const planner: Process [U32, U32, U32] = { init: init_p, step: step_p }",
    ),
    true,
  );
  equal(formatted.includes("spark #[@u32.add x x | x <- xs]"), true);
  equal(formatted.includes("spark #[x | x <- 0 .. n]"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves grouped curried parameter lists and named record calls", async () => {
  const source =
    `const area=func (width:U32) -> (height:U32)=> return @u32.mul width height
const named=func (fields:{width:U32,height:U32})=> return area fields.width fields.height
io const answer=func ()=> return named {height:3,width:4}
`;
  const formatted = await formatSource(source);
  equal(
    formatted.includes("func (width: U32) -> (height: U32) => return "),
    true,
  );
  equal(formatted.includes("named { height: 3, width: 4 }"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves continue and a flat pattern guard", async () => {
  const source = `type Candidate is data= $Keep U32| $Skip
io const kept=func (values:Array Candidate)=> return do:
  let total=0
  for candidate in values:
    let $Keep value=candidate else:
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
const descriptor=func code=> return code
const left:code [U32,row {}]=@code.quote 40
const shape:descriptor (code [U32,row {Foreign}])=@code.describe left
const answer=@code.quote (@u32.add (@code.splice left) (@code.lift 2))
io const run=func ()=> return @code.emit answer
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("code [U32, row {}]"), true);
  equal(formatted.includes("descriptor (code [U32, row { Foreign }])"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter preserves erased proof annotations and exact operand grouping", async () => {
  const source =
    `const at:(values:Array a)->(index:U32)->(@proof.Index values index)->a=func values=> return func index=> return func proof=> return @array.get values index
const less:(values:List U32)->@proof.U32Lt (0) (@list.length values)=func values=> return @proof.lt 0 (@list.length values)
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
const read:(state:State a)->a!{state.get}=func input=> return input.get ()
const apply:(state:State a)->((Unit->a!{state.get|e})->a!{state.get|e})=func input=> return func callback=> return callback ()
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("(state: State a)"), true);
  equal(formatted.includes("((Unit -> a ! { state.get | e })"), true);
});

Deno.test("formatter preserves private opaque forwarding and constructor lambda syntax", async () => {
  const source = `export {Token as Ticket, make} from "./tokens"
private type Token is opaque=F32
type Box a is opaque={value:a}
private type Alias=U32
private type Choice is data= $Choice U32
private type Read a is contract={type_rep a}
private effect Hidden:Unit->U32
private type HiddenFamily is effect={ask:Unit->U32}
private const private=func opaque=> return opaque
private io const answer=func export=> return private export
const unwrap=func ($Box value)=> return value.value
const typed=func (value:U32)=> return value
const pattern=func ((left,right))=> return left
export {Box} from "./tokens"
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("private type Token is opaque = F32"), true);
  equal(
    formatted.includes(
      "private io const answer = func export => return private export",
    ),
    true,
  );
  equal(formatted.includes("func ($Box value)"), true);
  equal(formatted.includes("func ((left, right))"), true);
  equal(
    formatted.includes(
      'export { Token as Ticket, make } from "./tokens"',
    ),
    true,
  );
});

Deno.test({
  name: "formatter keeps source and forwarded opaque project Wasm identical",
  ignore: Deno.args[0] === undefined,
  async fn() {
    const { createZigProjectCompiler } = await import(
      "../../host/zig_project_client.ts"
    );
    const directory = await Deno.makeTempDir({
      prefix: "blot-format-opacity-",
    });
    try {
      const entry = `${directory}/main.blot`;
      const sources = {
        [entry]:
          'import {make} from "./tokens"\nimport * as facade from "./facade"\ntype Alias=facade.Ticket\nio const answer=func (value:F32)=> return facade.read (make value)\nio const folded=facade.read (make 40.0)\n',
        [`${directory}/tokens.blot`]:
          "type Token is opaque=F32\nprivate const offset=2.0\nconst make:F32->Token=func value=> return $Token (@f32.add value offset)\nconst read:Token->F32=func ($Token value)=> return value\nprivate const Token.hidden=read\n",
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
  | $Point {x:U32,y:U32}
const from = func value=> return value
io const answer=func ()=> return do:
  let point= $Point {x: 1,y:2} // keep this
  let values = array.map (.x) #[point]
  let choose = if :point==:($Point {x:2,y:3}) then 40 else 0
  break values[0]+choose + from (-1.0)
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r")), formatted);
  equal(await formatSource(source.replaceAll("\n", "\r\n")), formatted);
  equal(formatted.includes("values[0] + choose"), true);
  equal(formatted.includes("array.map .x #[point]"), true);
  equal(formatted.includes("  // keep this"), true);
  equal(formatted.includes("if :point == :$Point"), true);
});

Deno.test("formatter separates variants and preserves arithmetic and call grouping", async () => {
  const source =
    `type Drag is data = $Idle | $Draw { x: F32, y: F32, width: F32, height: F32 } | $Move { x: F32, y: F32 }
const apply = func f => return func value => return f value
io const answer = func x => return do:
    let total = (1 + 2) * x
    let value = apply (func value => return value) (total + 1)
    break ((value))
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("type Drag is data =\n  | $Idle\n  | $Draw"), true);
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
const get=func xs=> return xs[0]
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
const contract=func contract=> return contract
const twice:a->a where {Add a}=func value=> return value+value
const convert:a->b ! {|e} where {result "from" a b ! {|e}}=func value=> return @type.result "from" value
const unfinished=func (action:Action U32)=> return @hole
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
const combine:a->b->c where {Merge [a,b,c]}=func left=> return func right=> return @record.merge left right
const f=func (point:Point)=> return do:
    let {y,x}=point
    break combine point {x:y}
const value=f {y:2.0,x:40}
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("@record.merge left right"), true);
  equal(formatted.includes("combine point { x: y }"), true);
});

Deno.test("formatter accepts nominal record patterns and custom symbolic operators", async () => {
  const source = `import {(++),(+~) as (+|)} from "./ops"
type Vec2 is data = $Vec2 { x: F32, y: F32 }
func (><) (left:U32)->(right:U32):U32=> left*10+right
const length=func value=> return do:
    let $Vec2 {x,y:height}=value
    break x+height
const first=func value=> return case value of
    $Some ($Vec2 {x}) => x
    _ => 0.0
const sum=func ()=> return 4><2
const ref=func ()=> return (+) 20 22
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(
    formatted.includes('import { (++), (+~) as (+|) } from "./ops"'),
    true,
  );
  equal(
    formatted.includes(
      "func (><) (left: U32) -> (right: U32): U32 => left * 10 + right",
    ),
    true,
  );
  equal(formatted.includes("let $Vec2 { x, y: height } = value"), true);
  equal(formatted.includes("$Some ($Vec2 { x }) => x"), true);
  equal(formatted.includes("4 >< 2"), true);
  equal(formatted.includes("(+) 20 22"), true);
});

// Every public example and std module formats idempotently, and the formatted
// sources compile to the same Wasm as the originals.
Deno.test("formatter keeps public examples and std modules compiling to identical Wasm", async () => {
  const executable = Deno.args[0];
  const repo = new URL("../../", import.meta.url).pathname;
  const formatted: Record<string, string> = {};
  const examples: string[] = [];
  for (
    const directory of ["examples", "examples/generators", "std", "tests/std"]
  ) {
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
    "../../host/zig_project_client.ts"
  );
  const prelude = `${repo}std/prelude.blot`;
  const stdRoot = `${repo}std`;
  for (const entry of examples.sort()) {
    const options = {
      executable,
      entry,
      prelude,
      stdRoot,
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
const keep:a->(Identity.Item a) where{Identity a,type_eq (Identity.Item a) a}=func value=> return value
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
private impl ArraySource a:Source (Array a) where{type_eq a U32}={type Item=a,const first=func values=> return @array.get values 0}
const impl=func impl=> return impl
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(
    formatted.includes("private impl ArraySource a: Source (Array a)"),
    true,
  );
  equal(formatted.includes("type Item = a"), true);
  equal(
    formatted.includes(
      "const first = func values => return @array.get values 0",
    ),
    true,
  );
  equal(formatted.includes("const impl = func impl => return impl"), true);
});

Deno.test("formatter preserves usage qualifiers and contextual value names", async () => {
  const source = `const unique=1
const f:once (borrow r U32->shared U32)=func x=> return x
const g:cleanup (unique U32->Unit)=func x=> return ()
const h:borrow_mut r [U32]=unique
const i:many (U32->U32)=func x=> return x
const j:concurrent (U32->U32 ! {Foreign})=host
const concurrent=1
const share=@usage.share unique
const scope=@resource.scope acquire release (func resource=> return resource)
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("once (borrow r U32 -> shared U32)"), true);
  equal(formatted.includes("borrow_mut r [U32]"), true);
});

Deno.test("formatter preserves quantified binders and package opening scope", async () => {
  const source = `const forall=func pack=> return pack
 type Id=forall [a]=>a->a
 type Borrower=forall [a,row e,region r]=>borrow r a->a!{|e}
 type Item=exists [a] where {Render a}=>a
 const make=pack [U32] 42 as Item
 const read=func item=> return unpack item as [a] value in Render.show value
 const plain=func unpack=> return unpack 1
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

Deno.test("formatter preserves primitive boolean words and bare patterns", async () => {
  const source =
    `const choose=func (left:Bool)->(right:Bool)=> return left or right and false
io const classify=func (value:Bool)=> return case value of
  true=>1
  false=>0
`;
  const formatted = await formatSource(source);
  equal(formatted.includes("left or right and false"), true);
  equal(formatted.includes("true => 1"), true);
  equal(await formatSource(formatted), formatted);
});

Deno.test("formatter handles expression #for/#if, reflected updates, fork expressions, fixed arrays, and trailing-comma tuples", async () => {
  const source = `type Config is data = $Config { x: U32 = 10, y: #[4; F32] }
func build (): t =>
  return #for field in #fields t:
    #if field.has_default:
      break field.default
    #else:
      break 0
func mutate (a: own t) -> (arr: own #[t]) -> (v: #[n; T]): U32 =>
  let built = #for field in #fields t:
    break a.(field)
  let chosen = #if true:
    1
  #else:
    2
  #for field in #fields t:
    a.(field) := built.(field)
    arr[0].(field) := a.(f1).(f2)
  let preview = fork arr:
    arr[0] := a
    return arr.length
  use scoped <- fork a, arr:
    return preview + chosen
  let single = (1,)
  let pair = (1, 2,)
  let (first,) = single
  let (left, right,) = pair
  return scoped + first + left + right
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(formatted.includes("#[4; F32]"), true);
  equal(formatted.includes("#[n; T]"), true);
  equal(formatted.includes("a.(field) := built.(field)"), true);
  equal(formatted.includes("arr[0].(field) := a.(f1).(f2)"), true);
  equal(formatted.includes("let preview = fork arr:"), true);
  equal(formatted.includes("use scoped <- fork a, arr:"), true);
  equal(formatted.includes("let single = (1,)"), true);
  equal(formatted.includes("let pair = (1, 2,)"), true);
  equal(formatted.includes("let (first,) = single"), true);
  equal(formatted.includes("let (left, right,) = pair"), true);
});

Deno.test("formatter is strictly idempotent across the 80-char data declaration wrap threshold", async () => {
  const source =
    "type T is data = $First {a:U32,b:U32,c:U32} | $VAAAAAAAAAAAAAAAAAAAAAAAAAA\n";
  const once = await formatSource(source);
  const twice = await formatSource(once);
  equal(once, twice);
  equal(
    once,
    "type T is data =\n  | $First { a: U32, b: U32, c: U32 }\n  | $VAAAAAAAAAAAAAAAAAAAAAAAAAA\n",
  );
});

Deno.test("formatter preserves packed array %[...] / %[T] syntax without conflicting with modulo %", async () => {
  const source = `type Event is data = $Tick | $Val U32
func take (xs:own %[Event])->(ro:*%[U32]):%[U32]=>
  let empty:%[U32]=%[]
  let nums=%[1,2,3]
  let mapped=%[x*2 | x<-nums, x>1]
  let spread=%[0,...nums,4]
  let rem=10%3
  let op=(%) 10 3
  return spread
io main ():U32=>
  let p=%[$Tick,$Val 7]
  let q=take p (freeze %[1,2])
  return q.length
`;
  const formatted = await formatSource(source);
  equal(await formatSource(formatted), formatted);
  equal(
    formatted.includes(
      "func take (xs: own %[Event]) -> (ro: *%[U32]): %[U32] =>",
    ),
    true,
  );
  equal(formatted.includes("let empty: %[U32] = %[]"), true);
  equal(formatted.includes("let nums = %[1, 2, 3]"), true);
  equal(formatted.includes("let mapped = %[x * 2 | x <- nums, x > 1]"), true);
  equal(formatted.includes("let spread = %[0, ...nums, 4]"), true);
  equal(formatted.includes("let rem = 10 % 3"), true);
  equal(formatted.includes("let op = (%) 10 3"), true);
  equal(formatted.includes("let p = %[$Tick, $Val 7]"), true);
  equal(formatted.includes("let q = take p (freeze %[1, 2])"), true);
});
