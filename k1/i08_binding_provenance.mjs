// Fixed target machine-site linkage, never a runtime capability or admission.
import {decode} from './i08_machine_decode.mjs';
import {inspect} from './i08_machine_inspect.mjs';
import {verify as verifyWorker,diagnosticUnpinnedForTests as workerDiagnostic} from './i08_worker_flow.mjs';
import {verifyFlow,unsafeDiagnosticForTests as flowDiagnostic} from './i08_flow_verify.mjs';
function token(x){let v=x.imm;if(v!==undefined&&v!==null&&typeof v==='object')v=v.offset;else if([2,3,4,5,11].includes(x.op))v=null;return x.op.toString(16)+(v==null?'':':'+v);}
function find(ops,pattern){let a=pattern.trim().split(/\s+/),got=ops.map(token),found=[];outer:for(let i=0;i+a.length<=got.length;i++){for(let j=0;j<a.length;j++)if(got[i+j]!==a[j])continue outer;found.push(i);}if(found.length!==1)throw Error('expected unique machine segment '+pattern);return found[0];}
function cfg(ops){
 const outer={kind:0,at:-1,end:ops.length-1,otherwise:-1},stack=[outer],labels=[],contexts=new Map();
 for(let i=0;i<ops.length;i++){labels[i]=stack.slice();let op=ops[i].op;if(op===2||op===3||op===4){let c={kind:op,at:i,end:-1,otherwise:-1};contexts.set(i,c);stack.push(c);}else if(op===5){let c=stack.at(-1);if(!c||c.kind!==4||c.otherwise>=0)throw Error('else');c.otherwise=i;}else if(op===11){let c=stack.pop();if(!c)throw Error('end');c.end=i;if(c===outer&&i!==ops.length-1)throw Error('end');}}
 if(stack.length)throw Error('blocks');let edges=ops.map(()=>[]),add=(i,j)=>{if(j>=0&&j<ops.length)edges[i].push(j);};
 for(let i=0;i<ops.length;i++){let x=ops[i],op=x.op;if(op===0||op===15||(op===11&&i===ops.length-1))continue;if(op===4){let c=contexts.get(i);add(i,i+1);add(i,c.otherwise>=0?c.otherwise+1:c.end+1);continue;}if(op===5){let c=labels[i].at(-1);if(!c||c.kind!==4)throw Error('else');add(i,c.end+1);continue;}if(op===12||op===13){let s=labels[i],c=s[s.length-1-x.imm];if(!c)throw Error('branch');if(c!==outer)add(i,c.kind===3?c.at+1:c.end+1);if(op===13)add(i,i+1);continue;}add(i,i+1);}return edges;
}
function reachable(e,start,target,skip=-1){if(start===undefined)return false;let seen=new Uint8Array(e.length),todo=[start];while(todo.length){let n=todo.pop();if(n===skip||seen[n])continue;if(n===target)return true;seen[n]=1;for(let k of e[n])todo.push(k);}return false;}
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
function analyze(input,pinned){try{
 if(!(input instanceof Uint8Array))throw Error('target bytes');const n=typedLength.call(input);if(n<8||n>65536)throw Error('target size');const bytes=new Uint8Array(n);Uint8Array.prototype.set.call(bytes,input);
 if((pinned&&!inspect(bytes).ok)||!(pinned?verifyWorker(bytes):workerDiagnostic(bytes)).ok||!(pinned?verifyFlow(bytes):flowDiagnostic(bytes)).ok)throw Error('independent pinned machine prerequisites');
 const g=decode(bytes);if(!g.ok)throw Error('decoder');let c=g.bodies[22].ops,edges=cfg(c);
 const origin=find(c,'41:32800 28:0 21:5 41:32804 28:0 21:6');
 const guard=find(c,'20:5 41:8 4b 20:6 41:3 71 45 45 72 20:6 41:12 49 72 20:6 20:13 4b 72 4')+17;
 const allocation=find(c,'41:192 10:0 21:7');
 const slot=find(c,'20:7 41:1 47 4 0 b 41:32 28:0 21:8 20:7 20:8 20:5 10:5');
 const inputData=find(c,'20:7 20:8 20:5 10:5 45 45 4 0 b 41:264 28:0 21:9');
 const freeze=find(c,'20:7 20:8 10:6 20:5 47 4 0 b');
 const builder=find(c,'20:7 20:8 41:8 10:8 45 45 4 0 b 41:328 28:0 21:10');
 const record=find(c,'41:49280 20:5 45 4 41:0 5 20:9 b 36:0 41:49280 20:5 36:4 41:49280 41:32808 28:0 36:8 41:49280 20:10 36:12 41:49280 41:8 36:16 41:0 41:49312 41:49280 10:21');
 const target=record+25;if(c[target].op!==0x10||c[target].imm!==21)throw Error('canonical call');
 if(!(origin<guard&&guard<allocation&&allocation<slot&&slot<inputData&&inputData<freeze&&freeze<builder&&builder<record))throw Error('ordered sites');
 if(c[guard].op!==4||!reachable(edges,0,target)||reachable(edges,0,target,guard)||reachable(edges,edges[guard][0],target)||!reachable(edges,edges[guard][1],target))throw Error('count guard dominance');
 if(c.slice(origin+3,target).some(x=>(x.op===0x21||x.op===0x22)&&x.imm===5))throw Error('count overwritten');
 const dataWrite=c.findIndex((x,i)=>i>=inputData&&(x.op===0x21||x.op===0x22)&&x.imm===9),outputWrite=c.findIndex((x,i)=>i>=builder&&(x.op===0x21||x.op===0x22)&&x.imm===10);
 if(dataWrite<0||outputWrite<0||c.slice(dataWrite+1,target).some(x=>(x.op===0x21||x.op===0x22)&&x.imm===9)||c.slice(outputWrite+1,target).some(x=>(x.op===0x21||x.op===0x22)&&x.imm===10))throw Error('data origins overwritten');
 const slotguard=slot+3;if(!reachable(edges,0,target)||reachable(edges,0,target,slotguard)||reachable(edges,edges[slotguard][0],target)||!reachable(edges,edges[slotguard][1],target))throw Error('slot guard dominance');
 let adapter=g.bodies[21].ops,shim=g.bodies[20].ops,project=g.bodies[9].ops;
 find(adapter,'41:49152 20:2 28:0 36:0 41:49152 20:2 28:4 36:4 41:49152 20:2 28:8 36:8 41:49152 20:2 28:12 36:12 41:49152 20:2 28:16 36:20 41:49152 41:0 36:16 41:0 41:49184 41:49152 10:20');
 find(shim,'20:2 28:0 41:264 28:0 47 4 0 b 20:2 28:4 41:268 28:0 47 4 0 b 20:2 28:12 41:328 28:0 47 4 0 b 20:2 28:16 41:332 28:0 47 4 0 b 20:2 28:20 41:384 28:0 47 4 0 b 41:1 41:32 28:0 41:1 41:32 28:0 20:2 2a:8 10:15');
 find(project,'20:7 28:8 20:9 20:13 20:8 20:10 20:4 10:10');
 return {ok:true,guardedCount:8,reservation:192,ownerSlot:1,outputCapacity:8,conditionalHelperSemantics:true,sourceGateRequired:true,eligible:false,m11Qualified:false};
 }catch(e){return {ok:false,error:String(e),eligible:false,m11Qualified:false};}}

export function check(bytes){return analyze(bytes,true);}
export function diagnosticForTests(bytes){return analyze(bytes,false);}
