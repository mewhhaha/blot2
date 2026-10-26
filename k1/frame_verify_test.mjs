import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {verify} from './frame_verify.mjs';
const target=readFileSync('frame-arena.wasm'),source=readFileSync('live-worker.wasm');assert(verify(target,source));
for(let i=0;i<target.length;i++){const m=Buffer.from(target);m[i]^=1;assert(!verify(m,source));assert(!verify(target.subarray(0,i),source));}
const appended=Buffer.concat([target,Buffer.of(0)]);assert(!verify(appended,source));
console.log('independent frame machine bytes, mutations and truncations verified');
