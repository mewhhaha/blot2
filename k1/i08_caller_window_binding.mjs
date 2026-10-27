// Pinned fixed-caller guard/loop shape linkage; no capability or M11 admission.
import {decode} from './i08_machine_decode.mjs';
import {check as base} from './i08_binding_provenance.mjs';
function token(x){let v=x.imm;if(v!==undefined&&v!==null&&typeof v==='object')v=v.offset;else if([2,3,4,5,11].includes(x.op))v=null;return x.op.toString(16)+(v==null?'':':'+v);}
function find(c,p){let a=p.split(' '),b=c.map(token),matches=[];outer:for(let i=0;i+a.length<=b.length;i++){for(let j=0;j<a.length;j++)if(a[j]!==b[i+j])continue outer;matches.push(i);}if(matches.length!==1)throw Error('missing or ambiguous shape '+p);return matches[0];}
function cfg(ops){
 const outer={kind:0,at:-1,end:ops.length-1,otherwise:-1},stack=[outer],labels=[],contexts=new Map();
 for(let i=0;i<ops.length;i++){labels[i]=stack.slice();let op=ops[i].op;if(op===2||op===3||op===4){let c={kind:op,at:i,end:-1,otherwise:-1};contexts.set(i,c);stack.push(c);}else if(op===5){let c=stack.at(-1);if(!c||c.kind!==4||c.otherwise>=0)throw Error('else');c.otherwise=i;}else if(op===11){let c=stack.pop();if(!c)throw Error('end');c.end=i;if(c===outer&&i!==ops.length-1)throw Error('end');}}
 if(stack.length)throw Error('blocks');let edges=ops.map(()=>[]),add=(i,j)=>{if(j>=0&&j<ops.length)edges[i].push(j);};
 for(let i=0;i<ops.length;i++){let x=ops[i],op=x.op;if(op===0||op===15||(op===11&&i===ops.length-1))continue;if(op===4){let c=contexts.get(i);add(i,i+1);add(i,c.otherwise>=0?c.otherwise+1:c.end+1);continue;}if(op===5){let c=labels[i].at(-1);if(!c||c.kind!==4)throw Error('else');add(i,c.end+1);continue;}if(op===12||op===13){let s=labels[i],c=s[s.length-1-x.imm];if(!c)throw Error('branch');if(c!==outer)add(i,c.kind===3?c.at+1:c.end+1);if(op===13)add(i,i+1);continue;}add(i,i+1);}return edges;
}
function reachable(e,start,target,skip=-1){if(start===undefined)return false;let seen=new Uint8Array(e.length),todo=[start];while(todo.length){let n=todo.pop();if(n===skip||seen[n])continue;if(n===target)return true;seen[n]=1;for(let k of e[n])todo.push(k);}return false;}
const getLen=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
export function bind(target){try{
 if(!(target instanceof Uint8Array))throw Error('target bytes');let n=getLen.call(target);if(n<8||n>65536)throw Error('target size');let snapshot=new Uint8Array(n);Uint8Array.prototype.set.call(snapshot,target);
 if(!base(snapshot).ok)throw Error('source-gated pinned site binding required');const g=decode(snapshot);if(!g.ok)throw Error('decode');let c=g.bodies[22].ops;
 let limits=find(c,'20:0 41:91 47 20:1 41:44 49 72 20:1 41:256 4b 72 20:2 41:224 4b 72 4');
 let origin=find(c,'20:1 41:32 6b 21:13 41:32800 28:0 21:5 41:32804 28:0 21:6');
 let range=find(c,'20:5 41:16 6c 20:13 20:6 6b 4b 4');
 let padding=find(c,'41:12 21:12 2 3 20:12 20:13 4f d:1 20:12 20:6 49 20:12 20:6 20:5 41:16 6c 6a 4f 72 4 41:32800 20:12 6a 2d:0');
 let input=find(c,'41:264 28:0 21:9 41:0 21:12 2 3 20:12 20:5 41:16 6c 4f d:1 20:9 20:12 6a 41:32800 20:6 6a 20:12 6a 2d:0 3a:0 20:12 41:1 6a 21:12 c:0 b b');
 let output=find(c,'41:8 20:5 41:8 6c 6a 21:11 41:0 21:3 20:11 20:2 4b 4 41:2 21:3 5 41:36896 20:5 36:0 41:36900 41:8 36:0 41:0 21:12 2 3 20:12 20:5 41:8 6c 4f d:1 41:36904 20:12 6a 20:10 20:12 6a 2d:0 3a:0 20:12 41:1 6a 21:12 c:0 b b b');
 if(!(limits<origin&&origin<range&&range<padding&&padding<input&&input<output))throw Error('site order');
 let edges=cfg(c);for(let guard of [limits+15,range+7])for(let target of [padding,input,output]){
  if(c[guard].op!==4||!reachable(edges,0,target)||reachable(edges,0,target,guard)||reachable(edges,edges[guard][0],target)||!reachable(edges,edges[guard][1],target))throw Error('guard dominance');
 }
 let capacityGuard=output+11,outputStore=output+38;
 if(c[capacityGuard].op!==4||c[outputStore].op!==0x3a||reachable(edges,0,outputStore,capacityGuard)||reachable(edges,edges[capacityGuard][0],outputStore)||!reachable(edges,edges[capacityGuard][1],outputStore))throw Error('capacity branch');
 for(let [guard,target] of [[padding+7,padding+23],[input+12,input+21],[output+30,output+37]]){
  if(c[guard].op!==13||!reachable(edges,0,target)||reachable(edges,0,target,guard)||reachable(edges,edges[guard][0],target)||!reachable(edges,edges[guard][1],target))throw Error('loop bound dominance');
 }
 for(let local of [1,2])if(c.some(x=>(x.op===0x21||x.op===0x22)&&x.imm===local))throw Error('argument overwritten');
 for(let local of [5,6,13]){let writes=c.flatMap((x,i)=>(x.op===0x21||x.op===0x22)&&x.imm===local?[i]:[]);if(writes.length!==1||writes[0]<origin||writes[0]>=range)throw Error('guard local rewritten');}
 return {ok:true,conditional:true,siteShapes:[limits,origin,range,padding,input,output],sourceGateRequired:true,assumesHelperGeometry:true,m11Qualified:false,publicEligible:false};
 }catch(e){return {ok:false,error:String(e),m11Qualified:false,publicEligible:false};}}
