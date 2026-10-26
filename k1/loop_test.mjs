// Executed private U32 copy-loop model. This is not a public K1 ABI, full
// resource/loan qualification, generic loop support or source particle I08.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
function bytes(name) { const b=readFileSync(name); assert(WebAssembly.validate(b)); return b; }
function instantiate(name) {
  const mod=new WebAssembly.Module(bytes(name));
  assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[['run','function'],['at','function'],['length','function'],['capacity','function']]);
  return new WebAssembly.Instance(mod).exports;
}
// Decode every normal-body instruction. The loop has one input load, one
// output store, then one initialized-length store; it calls no helper.
{
  const b=bytes('loop-fixture.wasm');
  function leb(p) { let n=0,s=0,v; do { assert(p.i<b.length); v=b[p.i++]; n+=(v&127)*2**s; s+=7; assert(s<=35); } while(v&128); return n; }
  const noarg=new Set([0x00,0x0b,0x0f,0x4b,0x4f,0x6a,0x6c]); let bodyCount=0, loopSeen=0;
  for(const p={i:8};p.i<b.length;) {
    const id=b[p.i++],len=leb(p),end=p.i+len; assert(end<=b.length);
    if(id===10) {
      assert.equal(leb(p),4);
      for(let fn=0;fn<4;fn++) {
        const size=leb(p),finish=p.i+size; assert(finish<=end);
        const groups=leb(p); for(let j=0;j<groups;j++) { leb(p); assert.equal(b[p.i++],0x7f); }
        let depth=0,inLoop=false,loopDepth=0; const ops=[];
        while(p.i<finish) {
          const op=b[p.i++]; assert.notEqual(op,0x40);
          if(op===0x0b) { if(inLoop && depth===loopDepth) inLoop=false; if(depth>0) depth--; continue; }
          if(op===0x02 || op===0x03 || op===0x04) {
            const typ=b[p.i++]; assert([0x40,0x7f].includes(typ)); depth++;
            if(fn===0 && op===0x03) { assert(!inLoop); inLoop=true; loopDepth=depth; loopSeen++; }
            continue;
          }
          let arg;
          if(op===0x28 || op===0x36) { assert.equal(leb(p),2); arg=leb(p); }
          else if([0x0c,0x0d,0x20,0x21,0x41].includes(op)) arg=leb(p);
          else if(!noarg.has(op)) assert.fail(`unexpected opcode 0x${op.toString(16)}`);
          if(fn===0 && inLoop) ops.push(arg===undefined ? [op] : [op,arg]);
        }
        if(fn===0) assert.deepEqual(ops,[
          [0x20,2],[0x20,0],[0x4f],[0x0d,1],
          [0x41,1024],[0x20,2],[0x41,4],[0x6c],[0x6a],
          [0x41,64],[0x20,2],[0x41,4],[0x6c],[0x6a],[0x28,0],[0x36,0],
          [0x41,16],[0x20,2],[0x41,1],[0x6a],[0x36,0],
          [0x20,2],[0x41,1],[0x6a],[0x21,2],[0x0c,0],
        ]);
        assert.equal(p.i,finish); bodyCount++;
      }
    } else p.i=end;
    assert.equal(p.i,end);
  }
  assert.equal(bodyCount,4); assert.equal(loopSeen,1);
}
function check(name, values) {
  const e=instantiate(name);
  assert.equal(e.length(),0); assert.equal(e.capacity(),0);
  assert.throws(()=>e.at(0),WebAssembly.RuntimeError);
  for(let n=0;n<=values.length;n++) {
    const cap=Math.min(128,n+((n%3)===0?0:2));
    assert.equal(e.run(n,cap),n); assert.equal(e.length(),n); assert.equal(e.capacity(),cap);
    for(let i=0;i<n;i++) assert.equal(e.at(i)>>>0,values[i]>>>0);
    assert.throws(()=>e.at(n),WebAssembly.RuntimeError);
    assert.throws(()=>e.at(-1),WebAssembly.RuntimeError);
  }
  const lastLength=e.length(),lastCap=e.capacity();
  const before=Array.from({length:lastLength},(_,i)=>e.at(i)>>>0);
  for(const [n,c] of [[values.length+1,128],[0,129],[1,0],[-1,128],[0,-1]]) {
    assert.equal(e.run(n,c),-1); assert.equal(e.length(),lastLength); assert.equal(e.capacity(),lastCap);
    assert.deepEqual(Array.from({length:lastLength},(_,i)=>e.at(i)>>>0),before);
  }
}
check('loop-fixture.wasm',[42,0xffffffff,0,123456789]);
check('loop-empty.wasm',[]);
check('loop-max.wasm',Array.from({length:128},(_,i)=>(Math.imul(i,65537)^0xa5a5a5a5)>>>0));
// Separate test-only traps occur at every prefix; the live builder length
// exposes exactly the already-written prefix. A real trapped bridge is
// poisoned; these raw fixture instances are discarded after inspection.
for(let prefix=0;prefix<=4;prefix++) {
  const e=instantiate(`loop-fault-${prefix}.wasm`), values=[42,0xffffffff,0,123456789];
  assert.throws(()=>e.run(4,4),WebAssembly.RuntimeError);
  assert.equal(e.length(),prefix); assert.equal(e.capacity(),4);
  for(let i=0;i<prefix;i++) assert.equal(e.at(i)>>>0,values[i]>>>0);
  assert.throws(()=>e.at(prefix),WebAssembly.RuntimeError);
}
// The second family traps after writing the current scalar but before
// publishing i+1. Only the previous prefix is observable; the just-written
// physical word is inaccessible through the checked initialized-length view.
for(let index=0;index<4;index++) {
  const e=instantiate(`loop-mid-${index}.wasm`), values=[42,0xffffffff,0,123456789];
  assert.throws(()=>e.run(4,4),WebAssembly.RuntimeError);
  assert.equal(e.length(),index); assert.equal(e.capacity(),4);
  for(let i=0;i<index;i++) assert.equal(e.at(i)>>>0,values[i]>>>0);
  assert.throws(()=>e.at(index),WebAssembly.RuntimeError);
}
console.log('private source-bound carry-loop Wasm execution passed');
