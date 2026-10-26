// Private fixed-backing guarded-read execution, not an actual K1 View ABI.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
function check(name, values) {
  const bytes=readFileSync(name); assert(WebAssembly.validate(bytes));
  const mod=new WebAssembly.Module(bytes); assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[['read','function']]);
  // Decode the entire function: preflight and the strict source guard precede
  // the sole load; no imported call, store, unregistered op or grow occurs.
  function leb(p) { let n=0,s=0,b; do { assert(p.i<bytes.length); b=bytes[p.i++]; n+=(b&127)*2**s; s+=7; assert(s<=35); } while(b&128); return n; }
  const plain=new Set([0x00,0x05,0x0b,0x49,0x4b,0x6a,0x6c]); let bodyCount=0;
  for(const p={i:8};p.i<bytes.length;) {
    const id=bytes[p.i++], size=leb(p), end=p.i+size; assert(end<=bytes.length);
    if(id===10) {
      assert.equal(leb(p),1); const len=leb(p), finish=p.i+len; assert(finish<=end); assert.equal(leb(p),0);
      const ops=[];
      while(p.i<finish) {
        const op=bytes[p.i++]; assert.notEqual(op,0x40); ops.push(op);
        if(plain.has(op)) continue;
        if(op===0x04) { assert([0x40,0x7f].includes(bytes[p.i++])); continue; }
        if(op===0x20 || op===0x41) { leb(p); continue; }
        if(op===0x28) { assert.equal(leb(p),2); assert.equal(leb(p),0); continue; }
        assert.fail(`unexpected opcode 0x${op.toString(16)}`);
      }
      assert.equal(ops.filter(x=>x===0x4b).length,1); assert.equal(ops.filter(x=>x===0x49).length,1);
      assert.equal(ops.filter(x=>x===0x28).length,1); assert(ops.indexOf(0x49)<ops.indexOf(0x28));
      assert.equal(p.i,finish); bodyCount++;
    } else p.i=end;
    assert.equal(p.i,end);
  }
  assert.equal(bodyCount,1);
  const read=new WebAssembly.Instance(mod).exports.read;
  for(let n=0;n<=values.length;n++) for(const i of [0,1,2,3,4,5,0xffffffff]) {
    assert.equal(read(n,i)>>>0, (i<n ? values[i] : 0xdeadbeef)>>>0, `n=${n} i=${i}`);
  }
  if(values.length===256) for(let n=0;n<=256;n++) for(let i=0;i<=257;i++)
    assert.equal(read(n,i)>>>0,(i<n ? values[i] : 0xdeadbeef)>>>0,`maximum n=${n} i=${i}`);
  assert.throws(()=>read(values.length+1,0),WebAssembly.RuntimeError);
}
check('bounds-fixture.wasm',[42,0xffffffff,0,123456789]);
check('bounds-empty.wasm',[]);
check('bounds-maximum.wasm',Array.from({length:256},(_,i)=>(Math.imul(i,65537)^0xa5a5a5a5)>>>0));
console.log('private guarded-view Wasm execution passed');
