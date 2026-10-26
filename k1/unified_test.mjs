import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
function uleb(bytes, p) { let v=0,shift=0; for (;;) { assert.ok(p<bytes.length && shift<=28); const b=bytes[p++];v+=(b&127)*2**shift;if(!(b&128))return[v,p];shift+=7; } }
function inspect(bytes) {
  let p=8,code=false,traps=0;
  while(p<bytes.length) {
    const section=bytes[p++];let size;[size,p]=uleb(bytes,p);const end=p+size;assert.ok(end<=bytes.length);
    if(section!==10){p=end;continue;}assert.equal(code,false);code=true;
    let funcs,body;[funcs,p]=uleb(bytes,p);assert.equal(funcs,1);[body,p]=uleb(bytes,p);assert.equal(p+body,end);
    let groups;[groups,p]=uleb(bytes,p);assert.ok(groups===0||groups===1);
    if(groups){let count;[count,p]=uleb(bytes,p);assert.ok(count<=128);assert.equal(bytes[p++],0x7f);}
    while(p<end){const op=bytes[p++];
      if(op===0x20||op===0x21){let index;[index,p]=uleb(bytes,p);assert.ok(index>=1&&index<=129);}
      else if(op===0x41){let b,n=0;do{assert.ok(p<end&&n++<5);b=bytes[p++];}while(b&128);}
      else if(op===0x04){assert.ok(bytes[p]===0x40||bytes[p]===0x7f);p++;}
      else if(op===0x00)traps++;
      else assert.ok([0x05,0x0b,0x0f,0x49,0x6a,0x6b,0x6c,0x71].includes(op),`unexpected opcode ${op}`);
    }assert.equal(p,end);
  }assert.equal(code,true);return traps;
}
const expected=[
  x=>x,
  x=>{const y=(x+1)>>>0;if(y<10){const z=Math.imul(y,2)>>>0;return z<4?z:y;}return(y-1)>>>0;},
  x=>x<10?11:22,
  x=>x,
  x=>x<20?(x<5?(x+1)>>>0:x):99,
  x=>x<4?x&15:0xffffffff,
];
for(let i=0;i<expected.length;i++){
  const bytes=await readFile(`unified_${i}.wasm`);assert.equal(WebAssembly.validate(bytes),true);assert.equal(inspect(bytes),1);
  const module=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(module),[]);
  assert.deepEqual(WebAssembly.Module.exports(module),[{name:"f",kind:"function"}]);const f=new WebAssembly.Instance(module).exports.f;
  for(const x of [0,1,2,3,4,9,10,19,20,255,2147483648,4294967295])assert.equal(f(0,x)>>>0,expected[i](x)>>>0,`case ${i}, input ${x}`);
}
for(const [kind,skip,evaluate,want] of [["and",10,0,2],["or",0,10,1]]){
  const bytes=await readFile(`unified_${kind}_probe.wasm`);assert.equal(WebAssembly.validate(bytes),true);assert.equal(inspect(bytes),2);
  const f=(await WebAssembly.instantiate(bytes)).instance.exports.f;assert.equal(f(0,skip)>>>0,want);assert.throws(()=>f(0,evaluate),WebAssembly.RuntimeError);
}
console.log("private unified nested control, local and short-circuit execution passed");
