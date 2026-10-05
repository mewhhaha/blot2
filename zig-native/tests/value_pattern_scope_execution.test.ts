import { compileAndRun, equal } from "./compile_helpers.ts";
const source = `
type Pair is data = #Pair (U32,U32)
type Fields is data = #Fields { first: U32, second: U32 }
const first = fn actual => do:
  let expected = 7
  return case actual of
    #Pair (expected,^expected) => expected
    _ => 0
const second = fn actual => do:
  let expected = 7
  return case actual of
    #Pair (^expected,expected) => expected
    _ => 0
const fields = fn actual => do:
  let expected = 7
  return case actual of
    #Fields { first: expected, second: ^expected } => expected
    _ => 0
entry const first_value = fn value => first (#Pair (value,7))
entry const second_value = fn value => second (#Pair (7,value))
entry const fields_value = fn value => fields (#Fields { first: value, second: 7 })
entry const miss = fn value => first (#Pair (42,value))
entry const folded = first (#Pair (42,7))
entry const folded_miss = first (#Pair (7,42))
`;
for(const asynchronous of [false,true]) Deno.test(`value patterns keep enclosing tuple/record bindings (${asynchronous ? "JSPI" : "sync"})`, async () => {
  await compileAndRun(source, async guest => {
    equal(guest.read("folded"),42); equal(guest.read("folded_miss"),0);
    for(let iteration=0;iteration<100;iteration++)for(const value of [0,7,42,0x80000000,0xffffffff]){
      for(const name of ["first_value","second_value","fields_value"]){
        const result = asynchronous ? await guest.callAsync(name,value) : guest.call(name,value);
        equal(result,value);
      }
      const result = asynchronous ? await guest.callAsync("miss",value) : guest.call("miss",value);
      equal(result,value===7 ? 42 : 0);
    }
  },{asynchronous});
});
