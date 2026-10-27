import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {decode} from './i08_machine_decode.mjs';
import {geometry,verify,diagnosticUnpinnedForTests} from './i08_worker_flow.mjs';
let b=readFileSync('private-invoke.wasm'),g=decode(b),r=verify(b);assert(r.ok,r.error);assert.equal(r.m11Qualified,false);assert.equal(r.eligible,false);
const w=g.bodies[10].ops,p=g.bodies[9].ops;let variants=0;
function reject(name,change){let x=Uint8Array.from(b);change(x);assert(WebAssembly.validate(x),name+' must validate');let d=diagnosticUnpinnedForTests(x);assert(!d.ok,name+' '+JSON.stringify(d));assert(!verify(x).ok,name+' pin');variants++;}
reject('loop boundary changed',x=>x[w[6].at]=0x4b);
reject('input stride changed',x=>x[w[10].at+1]=8);
reject('output stride changed',x=>x[w[42].at+1]=16);
reject('output element field changed',x=>x[w[53].at+2]=8);
reject('initialized prefix wrong',x=>x[w[56].at+1]=0);
reject('initialized prefix descriptor wrong',x=>x[w[58].at+2]=8);
reject('project owner guard falls through',x=>x[p[8].at]=0x1a);
reject('project capacity guard falls through',x=>x[p[211].at]=0x1a);
for(const [name,index,offset,value] of [['zero-view-pointer',70,1,1],['zero-view-field',71,2,12],['freeze-state',74,1,1],['descriptor-field',75,2,4],['prefix-increment',56,1,2]])reject(name,x=>x[w[index].at+offset]=value);
let count=0;for(let n=0;n<=8;n++)for(let cap=0;cap<=8;cap++)for(let input=0;input<=192;input+=4)for(let output=0;output<=192;output+=4){let ie=input+16*n,oe=output+8*cap;let expect=n<=cap&&ie<=192&&oe<=192&&!(n&&cap&&input<oe&&output<ie);let actual=geometry(n,input,output,cap);assert.equal(actual.ok,expect,JSON.stringify({n,cap,input,output}));if(expect){assert.equal(actual.initialized,n);count++;}}
for(const args of [[9,0,128,8],[1,0,0,8],[1,184,0,8],[2,0,64,1],[0,0,0,9],[-1,0,0,8],[1,Number.MAX_SAFE_INTEGER,0,8]])assert.equal(geometry(...args).ok,false);
for(let i=0;i<b.length;i++){let x=Uint8Array.from(b);x[i]^=1;assert(!verify(x).ok,'mutation '+i);assert(!verify(b.subarray(0,i)).ok,'truncation '+i);}
console.log(JSON.stringify({variants,geometries:count,byteMutations:b.length,truncations:b.length}));
