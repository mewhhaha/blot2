import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {decode} from './i08_machine_decode.mjs';
import {check,diagnosticForTests} from './i08_binding_provenance.mjs';
const b=readFileSync(process.argv[2] || 'private-invoke.wasm'),g=decode(b);assert(check(b).ok);assert(diagnosticForTests(b).ok);
const c=g.bodies[22].ops,s=g.bodies[20].ops,p=g.bodies[9].ops;
for(const [name,fn,i,offset,value] of [['count',c,146,1,9],['reserve',c,392,1,0xc1],['slot',c,453,1,2],['capacity',c,510,1,7],['record',c,526,1,10],['shim',s,164,1,0x8c],['worker-count',p,215,1,10]]){
 const x=Uint8Array.from(b);x[fn[i].at+offset]=value;assert(WebAssembly.validate(x),name+' must validate');assert(!check(x).ok,name+' pin');assert(!diagnosticForTests(x).ok,name+' shape');console.log(name,'rejected');
}
console.log('fixed caller-to-worker machine sites bound, conditional on helper semantics and source gate');
