import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {join} from 'node:path';import {tmpdir} from 'node:os';import {pathToFileURL} from 'node:url';
import {create} from './scalar_host.mjs';
const source=Uint8Array.from(readFileSync('scalar-host-0.wasm'));
let original=Uint8Array.from(source),pending=create(original);original.fill(0);let h=await pending;
assert.deepEqual(h.invoke(0,2),{status:'Ok',value:42});
let touches=0;const evil=new Proxy({}, {get(){touches++;throw Error('must not coerce')}});
for(const x of [undefined,null,true,false,1n,Symbol('x'),evil,new Number(1),Infinity,-Infinity,0.5,-1,4294967296])assert.deepEqual(h.invoke(x,2),{status:'InvalidInput'});
for(const d of [undefined,null,true,false,1n,Symbol('x'),evil,new Number(2),Infinity,-Infinity,1.5,-1,4294967296])assert.deepEqual(h.invoke(1,d),{status:'DepthLimit'});
assert.equal(touches,0);assert.deepEqual(h.invoke(evil,evil),{status:'InvalidInput'});assert.equal(touches,0);
let a=h.invoke(1,2);a.status='forged';assert.deepEqual(h.invoke(1,2),{status:'Ok',value:11});
assert.deepEqual(h.invoke(-0,2),{status:'Ok',value:42});assert.deepEqual(h.invoke(1,2),{status:'Ok',value:11});
// Test-only valid Wasm with an impossible high status returned by a signed
// widening of a deliberately negative leaf result. Ordinary host pin rejects.
let b=Uint8Array.from(source),needle=[0,0x20,1,4,0x40,0x41,11],at=-1;for(let i=0;i<=b.length-needle.length;i++)if(needle.every((v,j)=>b[i+j]===v)){assert.equal(at,-1);at=i;}assert(at>=0);b[at+6]=0x7f;
let pos=8,codeEnd=0;function leb(){let x=0,k=0;for(;;){const v=b[pos++];x+=(v&127)*2**k;if(!(v&128))return x;k+=7;}}
while(pos<b.length){let id=b[pos++],n=leb(),end=pos+n;if(id===10){codeEnd=end;break;}pos=end;}assert(codeEnd>0);
let widen=-1;for(let i=pos;i<codeEnd;i++)if(b[i]===0xad){assert.equal(widen,-1);widen=i;}assert(widen>=0);b[widen]=0xac;assert(WebAssembly.validate(b));await assert.rejects(create(b));
const originalHex=Buffer.from(source).toString('hex'),patchedHex=Buffer.from(b).toString('hex');let host=readFileSync(new URL('./scalar_host.mjs',import.meta.url),'utf8');assert(host.includes(originalHex));let dir=mkdtempSync(join(tmpdir(),'scalar-invalid-status-'));let path=join(dir,'host.mjs');writeFileSync(path,host.replace(originalHex,patchedHex));let test=await import(pathToFileURL(path));let poisoned=await test.create(b);
assert.deepEqual(poisoned.invoke(1,2),{status:'Poisoned'});assert.deepEqual(poisoned.invoke(0,2),{status:'Poisoned'});
console.log('independent hostile JS, snapshot isolation and impossible-status poisoning controls passed');
