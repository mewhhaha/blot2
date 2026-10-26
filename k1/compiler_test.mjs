import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
function leb(b,p){let n=0,s=0;for(;;){assert.ok(p.i<b.length&&s<=28);let v=b[p.i++];n+=(v&127)*2**s;if(!(v&128))return n;s+=7;}}
function inspect(b){const p={i:8};let count=0;
 while(p.i<b.length){const id=b[p.i++],len=leb(b,p),end=p.i+len;assert.ok(end<=b.length);
  if(id===10){assert.equal(leb(b,p),1);const size=leb(b,p),finish=p.i+size;assert.equal(finish,end);const groups=leb(b,p);assert.ok(groups===0||groups===1);if(groups){const n=leb(b,p);assert.ok(n<=255);assert.equal(b[p.i++],0x7f);}
   while(p.i<finish){const op=b[p.i++];
    if([0x20,0x21,0x0c,0x0d].includes(op))leb(b,p);
    else if(op===0x41){let v,n=0;do{assert.ok(p.i<finish&&n++<5);v=b[p.i++];}while(v&128);}
    else if([0x02,0x03,0x04].includes(op))assert.ok([0x40,0x7f].includes(b[p.i++]));
    else assert.ok([0x00,0x05,0x0b,0x0f,0x49,0x4f,0x6a,0x6b,0x6c,0x71].includes(op),`unexpected 0x${op.toString(16)}`);
   }count++;assert.equal(p.i,finish);
  }else p.i=end;assert.equal(p.i,end);
 }assert.equal(count,1);}
const expected=[
 x=>x===0xffffffff?x:x+1,
 x=>x===0?17:x-1,
 x=>x===0?17:x,
 x=>x,
 x=>x,
 x=>x===0?7:1,
 x=>x===0?4:x-1,
 x=>x===0?9:x-1,
 x=>x===0?99:0,
 ()=>2,
];
for(let i=0;i<expected.length;i++){
 const b=readFileSync(`compiler_${i}.wasm`);assert(WebAssembly.validate(b));inspect(b);
 const module=new WebAssembly.Module(b);assert.deepEqual(WebAssembly.Module.imports(module),[]);
 assert.deepEqual(WebAssembly.Module.exports(module),[{name:'f',kind:'function'}]);const f=new WebAssembly.Instance(module).exports.f;
 for(const x of [0,1,2,3,5,17,100])assert.equal(f(0,x)>>>0,expected[i](x)>>>0,`case ${i}, input ${x}`);
 // The early-stop, break and return cases execute only one iteration at MAX.
 if([0,2,4,8,9].includes(i))assert.equal(f(0,0xffffffff)>>>0,expected[i](0xffffffff)>>>0,`case ${i}, MAX`);
}
console.log('tagged scalar and finite-loop Wasm execution passed');
