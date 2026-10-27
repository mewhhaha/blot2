// Narrow pinned fixture worker proof, not public admission or M11 authority.
import {decode} from './i08_machine_decode.mjs';
import {inspect} from './i08_machine_inspect.mjs';
import {verifyHelperStructure} from './m12_helper_structure.mjs';
const WORKER=`41:0 21:6 2 3 20:6 20:1 4f d:1
20:0 20:6 41:16 6c 6a 2a:0
20:0 20:6 41:16 6c 6a 2a:8 20:5 94 92 21:7
20:0 20:6 41:16 6c 6a 2a:4
20:0 20:6 41:16 6c 6a 2a:12 20:5 94 92 21:8
20:2 20:6 41:8 6c 6a 20:7 38:0
20:2 20:6 41:8 6c 6a 20:8 38:4
20:3 20:6 41:1 6a 36:12
20:6 41:1 6a 21:6 c:0 b b
20:1 45 4 20:3 41:0 36:8 b
20:3 41:2 36:0 20:1 b`.trim().split(/\s+/);
function tokens(ops){return ops.map(x=>{let op=x.op.toString(16),v=x.imm;if(v!==undefined&&v!==null&&typeof v==='object')v=v.offset;else if([2,3,4,5,11].includes(x.op))v=null;return v===undefined||v===null?op:`${op}:${v}`;});}
function cfg(ops){
 const outer={kind:0,at:-1,end:ops.length-1,otherwise:-1},stack=[outer],labels=[],contexts=new Map();
 for(let i=0;i<ops.length;i++){labels[i]=stack.slice();let op=ops[i].op;if(op===2||op===3||op===4){let c={kind:op,at:i,end:-1,otherwise:-1};contexts.set(i,c);stack.push(c);}else if(op===5){let c=stack.at(-1);if(!c||c.kind!==4||c.otherwise>=0)throw Error('else');c.otherwise=i;}else if(op===11){let c=stack.pop();if(!c)throw Error('end');c.end=i;if(c===outer&&i!==ops.length-1)throw Error('end');}}
 if(stack.length)throw Error('blocks');let edges=ops.map(()=>[]),add=(i,j)=>{if(j>=0&&j<ops.length)edges[i].push(j);};
 for(let i=0;i<ops.length;i++){let x=ops[i],op=x.op;if(op===0||op===15||(op===11&&i===ops.length-1))continue;if(op===4){let c=contexts.get(i);add(i,i+1);add(i,c.otherwise>=0?c.otherwise+1:c.end+1);continue;}if(op===5){let c=labels[i].at(-1);if(!c||c.kind!==4)throw Error('else');add(i,c.end+1);continue;}if(op===12||op===13){let s=labels[i],c=s[s.length-1-x.imm];if(!c)throw Error('branch');if(c!==outer)add(i,c.kind===3?c.at+1:c.end+1);if(op===13)add(i,i+1);continue;}add(i,i+1);}
 return edges;
}
function reaches(e,start,target,skip=-1){if(start===undefined)return false;let seen=new Uint8Array(e.length),todo=[start];while(todo.length){let n=todo.pop();if(n===skip||seen[n])continue;if(n===target)return true;seen[n]=1;for(let k of e[n])todo.push(k);}return false;}
function checkGraph(g){if(!g.ok||g.bodies.length!==23||!verifyHelperStructure(g))throw Error('helper structure');
 let w=g.bodies[10].ops,t=tokens(w);if(t.length!==WORKER.length||t.some((x,i)=>x!==WORKER[i]))throw Error('worker shape');
 let p=g.bodies[9].ops,e=cfg(p),calls=p.flatMap((x,i)=>x.op===16&&x.imm===10?[i]:[]);if(calls.length!==1)throw Error('worker call');let target=calls[0];
 let guards=[6,16,23,39,47,57,67,105,113,121,137,152,166,174,184,209];
 for(let i of guards){if(p[i].op!==4||!reaches(e,0,target)||reaches(e,0,target,i)||reaches(e,e[i][0],target)||!reaches(e,e[i][1],target))throw Error('project guard dominance '+i+' '+[reaches(e,0,target),reaches(e,0,target,i),reaches(e,e[i][0],target),reaches(e,e[i][1],target)]);}
 let we=cfg(w);for(let target of [13,19,29,35,46,53,58])if(reaches(we,0,target,7)||!reaches(we,we[7][1],target)||reaches(we,we[7][0],target))throw Error('loop bound');
 for(let target of [58,63])for(let must of target===63?[46,53,58]:[46,53])if(reaches(we,0,target,must))throw Error('write before prefix');
 return {projectGuards:guards.length,workerInstructions:t.length,helperStateQualified:false,m11Qualified:false};
}
// Pure checked arithmetic for the fixed invocation's 192-byte owner region;
// nonempty source and destination ranges must be disjoint. Metadata and
// initialization contents are caller obligations, not authenticated here.
export function geometry(n,inputOffset,outputOffset,capacity=8){
 const z={ok:false};if(![n,inputOffset,outputOffset,capacity].every(Number.isSafeInteger)||n<0||n>8||capacity<0||capacity>8||n>capacity||inputOffset<0||outputOffset<0||(inputOffset%4)||(outputOffset%4))return z;
 let ib=inputOffset,ie=ib+16*n,ob=outputOffset,oe=ob+8*capacity;if(ie>192||oe>192||(n>0&&capacity>0&&ib<oe&&ob<ie))return z;
 let initialized=0;for(let i=0;i<n;i++){let reads=[0,4,8,12].map(k=>ib+16*i+k),writes=[0,4].map(k=>ob+8*i+k);if(reads.some(a=>a<ib||a+4>ie)||writes.some(a=>a<ob||a+4>oe)||initialized!==i)throw Error('range invariant');initialized=i+1;}
 return {ok:true,readBytes:16*n,writtenBytes:8*n,initialized,qualified:false};
}
export function diagnosticUnpinnedForTests(bytes){try{return {ok:true,...checkGraph(decode(bytes)),eligible:false};}catch(e){return {ok:false,error:String(e),eligible:false,m11Qualified:false};}}
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
export function verify(bytes){try{if(!(bytes instanceof Uint8Array))throw Error('bytes');let n=typedLength.call(bytes);if(n<8||n>65536)throw Error('size');let copy=new Uint8Array(n);Uint8Array.prototype.set.call(copy,bytes);if(!inspect(copy).ok)throw Error('pin');return diagnosticUnpinnedForTests(copy);}catch(e){return {ok:false,error:String(e),eligible:false,m11Qualified:false};}}
