import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';import {resolve} from 'node:path';
const root=process.argv[2],name=process.argv[3];const bytes=readFileSync(resolve(root,name+'.wasm'));
const mod=new WebAssembly.Module(bytes);assert.deepEqual(WebAssembly.Module.imports(mod),[]);
const f=new WebAssembly.Instance(mod).exports.f;assert.equal(typeof f,'function');assert.equal(f.length,2);
let inputs,oracle;
if(name==='u32_less'){inputs=[0,1,6,7,8,2147483647,4294967295];oracle=x=>+(x<7);}
else if(name==='bool_branch'){inputs=[0,1];oracle=x=>x?7:3;}
else if(name==='bool_identity'){inputs=[0,1];oracle=x=>x;}
else if(name==='u32_identity'){inputs=[0,1,6,7,2147483647,4294967295];oracle=x=>x;}
else if(name==='u32_loop'){inputs=[0,1,2,7,100,10000];oracle=x=>x?x-1:17;}
else if(name==='u32_wrapping'){inputs=[0,1,7,2147483647,4294967295];oracle=x=>(x+1)>>>0;}
else throw Error('missing independent witness for '+name);
const outputs=inputs.map(x=>f(0,x)>>>0);assert.deepEqual(outputs,inputs.map(oracle));
console.log(JSON.stringify({name,inputs,outputs,imports:WebAssembly.Module.imports(mod),exports:WebAssembly.Module.exports(mod),arity:f.length}));
