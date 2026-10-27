import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {decode} from './i08_machine_decode.mjs';
import {check,diagnosticForTests} from './i08_copy_complete.mjs';
const bytes=readFileSync(process.argv[2] || 'private-invoke.wasm');
const verified=check(bytes);assert(verified.ok, verified.error);
const ops=decode(bytes).bodies[22].ops, a=verified.matchedCopySite;
const mutations=[['exit-strict',11,0,0x4b], ['dest-subtract',15,0,0x6b], ['source-subtract',20,0,0x6b], ['source-byte-offset',21,2,1], ['destination-byte-offset',22,2,1], ['freeze-result-test',34,0,0x46]];
for(const [name,index,offset,value] of mutations){
 const altered=Uint8Array.from(bytes); altered[ops[a+index].at+offset]=value;
 assert(WebAssembly.validate(altered), name+' is valid Wasm');
 assert(!check(altered).ok,name+' pin');assert(!diagnosticForTests(altered).ok,name+' shape');
}
for(let i=0;i<bytes.length;i++){const altered=Uint8Array.from(bytes);altered[i]^=1;assert(!check(altered).ok,'mutation '+i);}
for(let i=0;i<bytes.length;i++)assert(!check(bytes.subarray(0,i)).ok,'truncation '+i);
console.log(`independent: ${mutations.length} valid-Wasm loop/freeze mutations and ${bytes.length} byte changes/truncations rejected`);
