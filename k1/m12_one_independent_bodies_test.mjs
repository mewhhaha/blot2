import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {verify} from './frame_verify.mjs';
const one=readFileSync('one-module.wasm'),frame=readFileSync('frame-arena.wasm'),worker=readFileSync('live-worker.wasm');assert(verify(frame,worker));
function leb(b,p){let n=0,shift=0,v;do{assert(p.i<b.length);v=b[p.i++];n+=(v&127)*2**shift;shift+=7;assert(shift<=35);}while(v&128);return n;}
function bodies(b){assert.deepEqual(b.subarray(0,8),Buffer.from([0,97,115,109,1,0,0,0]));const p={i:8};while(p.i<b.length){const id=b[p.i++],len=leb(b,p),end=p.i+len;assert(end<=b.length);if(id!==10){p.i=end;continue;}const n=leb(b,p),result=[];for(let i=0;i<n;i++){const size=leb(b,p);assert(p.i+size<=end);result.push(b.subarray(p.i,p.i+size));p.i+=size;}assert.equal(p.i,end);return result;}throw Error('code missing');}
const a=bodies(one),b=bodies(frame),c=bodies(worker);assert.equal(a.length,22);assert.equal(b.length,20);assert.equal(c.length,15);for(let i=0;i<15;i++)assert.deepEqual(a[i],c[i]);for(let i=15;i<20;i++)assert.deepEqual(a[i],b[i]);
assert.equal(WebAssembly.Module.imports(new WebAssembly.Module(one)).length,0);console.log('independently validated worker and pinned frame bodies match the one-module target');
