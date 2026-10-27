// Private bounded decoder; it does not authenticate bytes or qualify M11.
// Call with a separately source/target-verified module. Unknown instructions,
// imports, indirect calls, malformed immediates or resource growth fail closed.
const MAX=65536;
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
function u32(b,p,end){let n=0,m=1,k=0,last=0;do{if(p.i>=end||k===5)throw Error('leb');last=b[p.i++];if(k===4&&(last&0xf0))throw Error('u32');n+=(last&127)*m;m*=128;k++;}while(last&128);if(k>1&&!(last&127))throw Error('noncanonical u32');return n;}
function s32(b,p,end){let n=0n,shift=0n,k=0,last=0;do{if(p.i>=end||k===5)throw Error('sleb');last=b[p.i++];n|=BigInt(last&127)<<shift;shift+=7n;k++;}while(last&128);
 if(last&64)n|=(-1n)<<shift;if(n< -2147483648n||n>2147483647n)throw Error('s32');
 let x=n,encoded=[];for(;;){let v=Number(x&127n);x>>=7n;const done=(x===0n&&!(v&64))||(x===-1n&&(v&64));encoded.push(done?v:v|128);if(done)break;}
 if(encoded.length!==k)throw Error('noncanonical s32');return Number(n);
}
function range(n,p,end){if(!Number.isSafeInteger(n)||n<0||n>end-p.i)throw Error('range');const a=p.i;p.i+=n;return a;}
function sections(b){if(b.length<8||b.length>MAX||Buffer.from(b.subarray(0,8)).compare(Buffer.from([0,97,115,109,1,0,0,0])))throw Error('header');let p={i:8},m=new Map();for(const id of [1,3,5,7,10]){if(p.i>=b.length||b[p.i++]!==id)throw Error('section');let n=u32(b,p,b.length),start=range(n,p,b.length);m.set(id,[start,p.i]);}if(p.i!==b.length)throw Error('trailing');return m;}
function types(b,s,e){let p={i:s},n=u32(b,p,e);if(n>32)throw Error('types');let arities=[];for(let i=0;i<n;i++){if(b[p.i++]!==0x60)throw Error('type');let a=u32(b,p,e);if(a>16)throw Error('params');for(let j=0;j<a;j++)if(![0x7f,0x7d].includes(b[p.i++]))throw Error('type');let z=u32(b,p,e);if(z>1)throw Error('results');for(let j=0;j<z;j++)if(![0x7f,0x7d].includes(b[p.i++]))throw Error('type');arities.push([a,z]);}if(p.i!==e)throw Error('types');return arities;}
function instructions(b,start,end,fnCount,params){let p={i:start},groups=u32(b,p,end),locals=params;if(groups>16)throw Error('locals');for(let i=0;i<groups;i++){let n=u32(b,p,end);locals+=n;if(locals>64||![0x7f,0x7d].includes(b[p.i++]))throw Error('locals');}
 let depth=1,ops=[],calls=[],memory=[];
 while(p.i<end){const at=p.i,op=b[p.i++];let imm=null;
  if(op===0x02||op===0x03||op===0x04){if(p.i>=end||![0x40,0x7f,0x7d].includes(b[p.i++]))throw Error('block');depth++;if(depth>256)throw Error('depth');}
  else if(op===0x05){if(depth<=1)throw Error('else');}
  else if(op===0x0b){depth--;if(depth===0){if(p.i!==end)throw Error('end');ops.push({at,op});return {ops,calls,memory};}if(depth<0)throw Error('end');}
  else if(op===0x0c||op===0x0d){imm=u32(b,p,end);if(imm>=depth)throw Error('branch');}
  else if(op===0x10){imm=u32(b,p,end);if(imm>=fnCount)throw Error('call');calls.push(imm);}
  else if(op>=0x20&&op<=0x22){imm=u32(b,p,end);if(imm>=locals)throw Error('local');}
  else if(op>=0x28&&op<=0x3e){const align=u32(b,p,end),offset=u32(b,p,end);if(align>3||offset>65535)throw Error('memarg');imm={align,offset};memory.push({at,op,align,offset});}
  else if(op===0x41){imm=s32(b,p,end);}
  else if(op===0x43){const s=range(4,p,end);imm=Buffer.from(b.subarray(s,p.i)).toString('hex');}
  else if(op===0x44){const s=range(8,p,end);imm=Buffer.from(b.subarray(s,p.i)).toString('hex');}
  else if(op===0x00||op===0x01||op===0x0f||op===0x1a||(op>=0x45&&op<=0xbf)){}
  else throw Error(`unsupported ${op.toString(16)} @ ${at}`);
  if(ops.length>=65536)throw Error('ops');ops.push({at,op,imm});
 }
 throw Error('unterminated');
}
export function decode(bytes){try{
 if(!(bytes instanceof Uint8Array))throw Error('bytes');const length=typedLength.call(bytes);
 if(length<8 || length>MAX)throw Error('size');const b=new Uint8Array(length);Uint8Array.prototype.set.call(b,bytes);
 if(!WebAssembly.validate(b))throw Error('wasm');const secs=sections(b);const ts=secs.get(1),fs=secs.get(3),cs=secs.get(10);const tt=types(b,...ts);
 let p={i:fs[0]},count=u32(b,p,fs[1]);if(count===0||count>256)throw Error('function count');const f=[];for(let i=0;i<count;i++){let type=u32(b,p,fs[1]);if(type>=tt.length)throw Error('function type');f.push(type);}if(p.i!==fs[1])throw Error('function');
 p={i:cs[0]};if(u32(b,p,cs[1])!==count)throw Error('code count');let bodies=[];
 for(let i=0;i<count;i++){let n=u32(b,p,cs[1]),s=range(n,p,cs[1]);bodies.push(instructions(b,s,p.i,count,tt[f[i]][0]));}if(p.i!==cs[1])throw Error('code');
 return {ok:true,types:tt,functions:f,bodies};
 }catch(e){return {ok:false,error:String(e)};}}
export function reachable(graph,root){if(!graph.ok||!Number.isInteger(root)||root<0||root>=graph.bodies.length)throw Error('root');
 const state=new Uint8Array(graph.bodies.length),order=[],depths=new Uint32Array(graph.bodies.length);
 function walk(n){if(state[n]===1)throw Error('cycle');if(state[n]===2)return depths[n];state[n]=1;let max=0;
  for(const v of graph.bodies[n].calls)max=Math.max(max,walk(v));state[n]=2;order.push(n);return depths[n]=max+1;}
 const depth=walk(root);return {depth,order,depths};}
