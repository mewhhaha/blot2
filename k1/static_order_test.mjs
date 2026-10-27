import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {openVerifiedFixture} from './static_publish_host.mjs';
const bytes=readFileSync('static-ordered.wasm');assert(WebAssembly.validate(bytes));
const a=openVerifiedFixture(bytes),b=openVerifiedFixture(bytes);const x=a.index(0),y=a.index(1);
assert.deepEqual([a.read(x,0),a.read(x,1),a.read(y,0),a.read(y,1)],[1,0x80000000,3,0x7fc00000]);
assert.throws(()=>b.read(x,0),TypeError);assert.throws(()=>a.index(2),RangeError);
console.log('ordered checked static target execution passed');
