// Private raw-F32 expression fixtures, not K1 function ABI or loop admission.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
function module(name) {
  const bytes = readFileSync(name); assert(WebAssembly.validate(bytes)); const mod = new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod), []);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x => [x.name,x.kind]), [['expr','function']]);
  return new WebAssembly.Instance(mod).exports.expr;
}
const x = module('particle-expr-x.wasm'), y = module('particle-expr-y.wasm'), group = module('particle-expr-group.wasm');
const round = Math.fround; let seed = 0x7654bb21;
const rand = () => (seed = (Math.imul(seed,1664525) + 1013904223) >>> 0);
const same = (got, want) => { if (Number.isNaN(want)) assert(Number.isNaN(got)); else assert(Object.is(got,want)); };
for (let i = 0; i < 2000; i++) {
  const [px,py,vx,vy,dt] = Array.from({length: 5}, () => round(((rand() % 200001) - 100000) / 256));
  same(x(px,py,vx,vy,dt), round(px + round(vx * dt)));
  same(y(px,py,vx,vy,dt), round(py + round(vy * dt)));
  same(group(px,py,vx,vy,dt), round(round(px + vx) * round(dt + py)));
}
same(x(1,0,Infinity,0,0), NaN); same(y(0,-0,0,-0,1), -0);
console.log('private source-bound F32 expression Wasm execution passed');
