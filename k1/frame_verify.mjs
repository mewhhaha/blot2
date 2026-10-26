// Private exact structural verifier: source-linked original must itself be
// independently revalidated by the caller. The three frame helper bytecodes
// are independently pinned, including preflight/restore and call index.
import {strict as assert} from 'node:assert';
const tails=[
 '01017f419c032802004101470440417b0f0b41980328020021054190032802004180204b0440417b0f0b20054190032802004b0440417b0f0b41800641900328020020056b4b0440417b0f0b41940328020020054180066a470440417b0f0b2000200120022003200410090b',
 '00419c0328020045450440417c0f0b41940328020045450440417c0f0b20004180204b0440417c0f0b419003200036020041000b',
 '004194032802000b',
 '01017f41900128020045450440417c0f0b412428020045412428020041034672450440417c0f0b41c4002802004541c40028020041034672450440417c0f0b41e4002802004541e40028020041034672450440417c0f0b4184012802004541840128020041034672450440417c0f0b419c0328020045450440417c0f0b41940328020021004190032802004180204b0440417b0f0b20004190032802004b0440417b0f0b41800641900328020020006b4b0440417b0f0b419803200036020041940320004180066a360200419c0341013602004180800320006a41003a000041000b',
 '01017f41900128020045450440417c0f0b412428020045412428020041034672450440417c0f0b41c4002802004541c40028020041034672450440417c0f0b41e4002802004541e40028020041034672450440417c0f0b4184012802004541840128020041034672450440417c0f0b419c032802004101470440417c0f0b41980328020021004190032802004180204b0440417c0f0b20004190032802004b0440417c0f0b41800641900328020020006b4b0440417c0f0b41940328020020004180066a470440417c0f0b4194032000360200419c03410036020041000b',
];
function read(b,p,end){let n=0,m=1,k=0,last;do{assert(p.i<end);last=b[p.i++];n+=(last&127)*m;m*=128;k++;assert(k<=5);}while(last&128);assert(k===1||(last&127)!==0);return n;}
function sections(b){assert.deepEqual(b.subarray(0,8),Buffer.from([0,97,115,109,1,0,0,0]));let p={i:8},out=[];
 while(p.i<b.length){let id=b[p.i++],n=read(b,p,b.length),end=p.i+n;assert(end<=b.length);out.push([id,b.subarray(p.i,end)]);p.i=end;}return out;}
function bodies(payload){let p={i:0},n=read(payload,p,payload.length),out=[];for(let i=0;i<n;i++){let len=read(payload,p,payload.length);assert(len<=payload.length-p.i);out.push(payload.subarray(p.i,p.i+len));p.i+=len;}assert.equal(p.i,payload.length);return out;}
function exports(payload){let p={i:0},n=read(payload,p,payload.length),out=[];for(let i=0;i<n;i++){const len=read(payload,p,payload.length);assert(len<=payload.length-p.i);let name=payload.subarray(p.i,p.i+len).toString();p.i+=len;assert(p.i<payload.length);const kind=payload[p.i++],idx=read(payload,p,payload.length);out.push([name,kind,idx]);}assert.equal(p.i,payload.length);return out;}
export function verify(frame,source){try {
 const a=sections(Buffer.from(frame)),b=sections(Buffer.from(source));assert.deepEqual(a.map(x=>x[0]),[1,3,5,7,10]);assert.deepEqual(b.map(x=>x[0]),[1,3,5,7,10]);
 assert.deepEqual(a[0][1],b[0][1]);assert.deepEqual(a[2][1],b[2][1]);
 assert.deepEqual(a[1][1],Buffer.from([20,0,1,2,0,1,3,1,3,3,4,5,1,1,1,1,4,0,2,2,2]));
 const expected=[['reserve',0,0],['close',0,11],['input_alloc',0,5],['input_freeze',0,6],['advance',0,7],['builder_alloc',0,8],['project',0,15],['input_end',0,12],['output_end',0,13],['input_discard',0,14],['frame_config',0,16],['frame_top',0,17],['frame_enter',0,18],['frame_leave',0,19],['memory',2,0]];
 assert.deepEqual(exports(a[3][1]),expected);const aa=bodies(a[4][1]),bb=bodies(b[4][1]);assert.equal(aa.length,20);assert.equal(bb.length,15);
 for(let i=0;i<15;i++)assert.deepEqual(aa[i],bb[i]);for(let i=0;i<5;i++)assert.deepEqual(aa[i+15],Buffer.from(tails[i],'hex'));
 return true;
 }catch{return false;}}
