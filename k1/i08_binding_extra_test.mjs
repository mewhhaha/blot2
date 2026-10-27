import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {decode} from './i08_machine_decode.mjs';import {check,diagnosticForTests} from './i08_binding_provenance.mjs';
const b=readFileSync(process.argv[2] || 'private-invoke.wasm'),c=decode(b).bodies[22].ops;assert(check(b).ok);
for(const [name,i,value] of [['input-data-field',470,0x8c],['output-data-field',517,0xcc],['output-local',519,9]]){
 let x=Uint8Array.from(b);x[c[i].at+1]=value;assert(WebAssembly.validate(x),name);assert(!diagnosticForTests(x).ok,name);console.log(name,'rejected');
}
