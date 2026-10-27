// Bounded fixture-specific control/dataflow proof. This checks only the
// source-pinned caller path and its two fixed adapter functions, not helpers,
// arbitrary public adapter entries, general Wasm or M11 qualification.
import {decode} from './i08_machine_decode.mjs';
import {inspect} from './i08_machine_inspect.mjs';
const FRAME_START=49152,FRAME_END=49920;
const range=(x,a,b)=>x>=a&&x+4<=b;
function cfg(ops){
 const n=ops.length,outer={kind:0,at:-1,end:n-1,otherwise:-1},stack=[outer],labels=[],contexts=new Map();
 for(let i=0;i<n;i++){
  labels[i]=stack.slice();const op=ops[i].op;
  if(op===0x02||op===0x03||op===0x04){const c={kind:op,at:i,end:-1,otherwise:-1};contexts.set(i,c);stack.push(c);}
  else if(op===0x05){const c=stack.at(-1);if(!c||c.kind!==0x04||c.otherwise>=0)throw Error('else');c.otherwise=i;}
  else if(op===0x0b){const c=stack.pop();if(!c)throw Error('end');c.end=i;if(c===outer&&i!==n-1)throw Error('function end');}
 }
 if(stack.length!==0)throw Error('blocks');
 const next=Array.from({length:n},()=>[]),edge=(i,j)=>{if(j>=0&&j<n)next[i].push(j);};
 for(let i=0;i<n;i++){
  const x=ops[i],op=x.op;
  if(op===0x00||op===0x0f||(op===0x0b&&i===n-1))continue;
  if(op===0x04){const c=contexts.get(i);edge(i,i+1);edge(i,c.otherwise>=0?c.otherwise+1:c.end+1);continue;}
  if(op===0x05){const c=labels[i].at(-1);if(!c||c.kind!==0x04)throw Error('else scope');edge(i,c.end+1);continue;}
  if(op===0x0c||op===0x0d){const ls=labels[i],c=ls[ls.length-1-x.imm];if(!c)throw Error('branch depth');if(c!==outer)edge(i,c.kind===0x03?c.at+1:c.end+1);if(op===0x0d)edge(i,i+1);continue;}
  edge(i,i+1);
 }
 return next;
}
function reachableFrom(edges,start,target,skip=-1){if(start===skip||start<0||start>=edges.length)return false;const seen=new Uint8Array(edges.length),stack=[start];while(stack.length){const i=stack.pop();if(i===skip||seen[i])continue;if(i===target)return true;seen[i]=1;for(const j of edges[i])stack.push(j);}return false;}
function dominates(edges,node,target){return reachableFrom(edges,0,target)&&!reachableFrom(edges,0,target,node);}
function findSequence(ops,sequence){outer:for(let i=0;i+sequence.length<=ops.length;i++){for(let j=0;j<sequence.length;j++){let x=ops[i+j],s=sequence[j];if(x.op!==s[0]||(s.length>1&&x.imm!==s[1]))continue outer;}return i;}throw Error('missing sequence');}
function sourcePreflight(graph){
 const ops=graph.bodies[22].ops,edges=cfg(ops),call=x=>{const all=[];ops.forEach((o,i)=>{if(o.op===0x10&&o.imm===x)all.push(i);});if(all.length!==1)throw Error('call multiplicity');return all[0];};
 const enter=call(18),reserve=call(0),input=call(5),freeze=call(6),builder=call(8),adapter=call(21);
 const top=findSequence(ops,[[0x41,404],[0x28],[0x45],[0x45],[0x04]])+4;
 if(ops[top-3].imm?.offset!==0)throw Error('frontier address');
 const enterCheck=enter+5;
 if(ops[enter+1]?.op!==0x21||ops[enter+1].imm!==14||ops[enter+2]?.op!==0x20||ops[enter+2].imm!==14||ops[enter+3]?.op!==0x45||ops[enter+4]?.op!==0x45||ops[enterCheck]?.op!==0x04)throw Error('enter result check');
 if(!dominates(edges,top,enter)||reachableFrom(edges,edges[top][0],enter)||!reachableFrom(edges,edges[top][1],enter))throw Error('entry preflight');
 for(const target of [reserve,input,freeze,builder,adapter]){
  if(!dominates(edges,top,target)||!dominates(edges,enter,target)||!dominates(edges,enterCheck,target))throw Error('preflight dominance');
  if(reachableFrom(edges,edges[top][0],target)||!reachableFrom(edges,edges[top][1],target))throw Error('top failure edge');
  if(reachableFrom(edges,edges[enterCheck][0],target)||!reachableFrom(edges,edges[enterCheck][1],target))throw Error('enter failure edge');
 }
 if(!dominates(edges,adapter-3,adapter)||!dominates(edges,adapter-2,adapter)||!dominates(edges,adapter-1,adapter))throw Error('arguments do not dominate');
 if(ops[adapter-3].op!==0x41||ops[adapter-3].imm!==0||ops[adapter-2].op!==0x41||ops[adapter-2].imm!==49312||ops[adapter-1].op!==0x41||ops[adapter-1].imm!==49280)throw Error('arguments');
 return {topGuard:top,enter,enterCheck,reserve,input,freeze,builder,adapter};
}
const eq=(a,b)=>a===b?a:null;
function merge(old,s){if(!old)return {locals:s.locals.slice(),stack:s.stack.slice()};if(old.stack.length!==s.stack.length||old.locals.length!==s.locals.length)throw Error('stack merge');
 let changed=false;for(let i=0;i<old.locals.length;i++){let n=eq(old.locals[i],s.locals[i]);if(n!==old.locals[i]){old.locals[i]=n;changed=true;}}
 for(let i=0;i<old.stack.length;i++){let n=eq(old.stack[i],s.stack[i]);if(n!==old.stack[i]){old.stack[i]=n;changed=true;}}return changed?old:null;}
function pop(s){if(!s.stack.length)throw Error('underflow');return s.stack.pop();}
function bit(x){return x===null?null:x>>>0;}
function applyBinary(op,a,b){if(a===null||b===null)return null;a>>>=0;b>>>=0;
 switch(op){case 0x46:return +(a===b);case 0x47:return +(a!==b);case 0x49:return +(a<b);case 0x4b:return +(a>b);case 0x4d:return +(a<=b);case 0x4f:return +(a>=b);case 0x6a:return (a+b)>>>0;case 0x6b:return (a-b)>>>0;case 0x6c:return Math.imul(a,b)>>>0;case 0x71:return (a&b)>>>0;case 0x72:return (a|b)>>>0;default:throw Error(`binary ${op}`);}}
function allowed(fn,op,addr){const w=4,end=addr+w;if(addr>=FRAME_END||end<=FRAME_START){const metadata=fn===21?[400,404,408,412]:[16,20,24,28,32,36,144,256,260,264,268,320,324,328,332,384];return op===0x28&&metadata.includes(addr);}
 if(fn===21){if(op===0x28)return range(addr,49280,49300)||range(addr,49184,49192);if(op===0x36)return range(addr,49152,49176)||range(addr,49312,49328);}
 if(fn===20){if(op===0x28||op===0x2a)return range(addr,49152,49176);if(op===0x36)return range(addr,49184,49192);}
 return false;
}
function analyzeAdapter(graph,fn,args){
 const ops=graph.bodies[fn].ops,edges=cfg(ops),states=Array(ops.length).fill(null),queue=[0],inQueue=new Uint8Array(ops.length),accesses=new Map();states[0]={locals:args.slice(),stack:[]};inQueue[0]=1;let steps=0;
 while(queue.length){if(++steps>100000)throw Error('flow bound');const i=queue.shift();inQueue[i]=0;const old=states[i],s={locals:old.locals.slice(),stack:old.stack.slice()},x=ops[i],op=x.op;let condition=null;
  if(op===0x41)s.stack.push(x.imm>>>0);
  else if(op===0x20){if(x.imm>=s.locals.length)throw Error('local');s.stack.push(s.locals[x.imm]);}
  else if(op===0x21){if(x.imm>=s.locals.length)throw Error('local');s.locals[x.imm]=pop(s);}
  else if(op===0x22){if(x.imm>=s.locals.length||!s.stack.length)throw Error('local');s.locals[x.imm]=s.stack.at(-1);}
  else if(op===0x45){const a=pop(s);s.stack.push(a===null?null:+(a===0));}
  else if([0x46,0x47,0x49,0x4b,0x4d,0x4f,0x6a,0x6b,0x6c,0x71,0x72].includes(op)){const b=pop(s),a=pop(s);s.stack.push(applyBinary(op,a,b));}
  else if(op===0x28||op===0x2a||op===0x36){if(op===0x36)pop(s);const base=pop(s);if(base===null)throw Error('unbounded address');
   const address=bit(base)+x.imm.offset;if(!Number.isSafeInteger(address)||address>0xffffffff||!allowed(fn,op,address))throw Error('unexpected slot');
   accesses.set(i,{instruction:i,op,address});if(op!==0x36)s.stack.push(null);
  }
  else if(op===0x10){const ty=graph.types[graph.functions[x.imm]],vals=[];for(let j=0;j<ty[0];j++)vals.unshift(pop(s));
   if(fn===21&&x.imm===20&&(vals[0]!==0||vals[1]!==49184||vals[2]!==49152))throw Error('shim arguments');
   for(let j=0;j<ty[1];j++)s.stack.push(null);
  }
  else if(op===0x04)condition=pop(s);
  else if(op===0x00||op===0x05||op===0x0b||op===0x02||op===0x03||op===0x0f){}
  else throw Error(`unsupported adapter instruction ${op.toString(16)}`);
  let next=edges[i];if(op===0x04&&condition!==null)next=[condition?edges[i][0]:edges[i][1]].filter(x=>x!==undefined);
  for(const j of next){const merged=merge(states[j],s);if(merged){states[j]=merged;if(!inQueue[j]){queue.push(j);inQueue[j]=1;}}}
 }
 return [...accesses.values()].sort((a,b)=>a.instruction-b.instruction);
}
// Diagnostic only: unpinned decoded inputs are never admissible authority.
export function unsafeDiagnosticForTests(target){try{
 const graph=decode(target);if(!graph.ok)throw Error('decode');
 const preflight=sourcePreflight(graph),adapter=analyzeAdapter(graph,21,[0,49312,49280]),shim=analyzeAdapter(graph,20,[0,49184,49152]);
 return {ok:true,preflight,adapter,shim,eligible:false,m11Qualified:false};
 }catch(e){return {ok:false,error:String(e),eligible:false,m11Qualified:false};}}
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
export function verifyFlow(target){try{
 if(!(target instanceof Uint8Array))throw Error('bytes');const n=typedLength.call(target);
 if(n<8||n>65536)throw Error('size');const copy=new Uint8Array(n);Uint8Array.prototype.set.call(copy,target);
 const pinned=inspect(copy);if(!pinned.ok)throw Error('source-target pin');const result=unsafeDiagnosticForTests(copy);if(!result.ok)throw Error(result.error);
 return {...result,machineDepth:pinned.machineDepth,adapterAndShimSlotsVerified:true,helpersQualified:false,m11Qualified:false};
 }catch(e){return {ok:false,error:String(e),eligible:false,m11Qualified:false};}}
