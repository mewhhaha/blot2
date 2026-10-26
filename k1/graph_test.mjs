// Private immutable graph-data execution witness, not K1 source or domain
// authority. The memory is not exported, so raw bytes cannot be forged by the
// test host after independent validation and module instantiation.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
function check(name, expected) {
  const bytes = readFileSync(name); assert(WebAssembly.validate(bytes));
  const mod = new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod), []);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x => [x.name,x.kind]), [['source','function'],['target','function']]);
  // Decoder verifies the complete small instruction language. Only the edge
  // index comparison exists; endpoint values are read directly from already
  // checked immutable bytes. No stores, indirect calls or memory.grow.
  function leb(p) { let n=0,s=0,b; do { assert(p.i<bytes.length); b=bytes[p.i++]; n+=(b&127)*2**s; s+=7; assert(s<=35); } while(b&128); return n; }
  const ops = new Set([0x00,0x0b,0x4f,0x6a,0x6c]); let bodies=0;
  for(const p={i:8};p.i<bytes.length;) {
    const id=bytes[p.i++], length=leb(p), end=p.i+length; assert(end<=bytes.length);
    if(id===10) {
      assert.equal(leb(p),2);
      for(let f=0;f<2;f++) {
        const size=leb(p), finish=p.i+size; assert(finish<=end); assert.equal(leb(p),0);
        let bounds=0,loads=0;
        while(p.i<finish) {
          const op=bytes[p.i++]; assert.notEqual(op,0x40);
          if(ops.has(op)) { if(op===0x4f) bounds++; continue; }
          if(op===0x04) { assert.equal(bytes[p.i++],0x40); continue; }
          if(op===0x20||op===0x41) { leb(p); continue; }
          if(op===0x28) { assert.equal(leb(p),2); leb(p); loads++; continue; }
          assert.fail(`unexpected graph opcode 0x${op.toString(16)}`);
        }
        assert.equal(bounds,1); assert.equal(loads,2); assert.equal(p.i,finish); bodies++;
      }
    } else p.i=end;
    assert.equal(p.i,end);
  }
  assert.equal(bodies,2);
  const e=new WebAssembly.Instance(mod).exports;
  for(let i=0;i<expected.length;i++) {
    assert.equal(e.source(i)>>>0, expected[i][0]>>>0);
    assert.equal(e.target(i)>>>0, expected[i][1]>>>0);
  }
  assert.throws(()=>e.source(expected.length),WebAssembly.RuntimeError);
  assert.throws(()=>e.target(-1),WebAssembly.RuntimeError);
}
check('graph-fixture.wasm',[[100,0xffffffff],[17,100]]);
check('graph-other.wasm',[[100,0xffffffff],[17,100]]);
check('graph-empty.wasm',[]);
check('graph-max.wasm',Array.from({length: 128}, (_, i) => [i, 127 - i]));
console.log('private checked stored-endpoint Wasm witness passed');
