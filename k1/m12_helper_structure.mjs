// Structural checks over decoded operations in the private source-checked target.
// This recognizes selected fixed guards and ordering only. It is not a general
// Wasm verifier and must be used after exact source/target verification.
function tokens(body) {
 return body.ops.map(({op,imm})=>op.toString(16)+(imm==null?'':':'+(typeof imm==='object'?imm.offset:imm)));
}
function scan(a,patterns) {
 let from=0;
 for(const text of patterns) {
  const p=text.split(' '); let found=-1;
  outer: for(let i=from;i+p.length<=a.length;i++){
   for(let j=0;j<p.length;j++)if(a[i+j]!==p[j])continue outer;
   found=i;break;
  }
  if(found<0) throw Error(`missing guard ${text}`);
  from=found+p.length;
 }
 return from;
}
function verifyBody(graph,index,patterns,lastBeforeStore=false) {
 const b=graph.bodies[index];if(!b) throw Error('missing body');
 const a=tokens(b),end=scan(a,patterns);
 if(lastBeforeStore && a.slice(0,end).some(x=>x.startsWith('36:')||x.startsWith('38:')||x.startsWith('3a:')))throw Error('store before guards');
 return a;
}
export function verifyHelperStructure(graph) {
 try {
 if(!graph?.ok || graph.bodies.length!==23)throw Error('graph');
 // The owner handle must be in 1..4 and generation nonzero before deriving
 // slot pointer; state/generation/extent and bitmap are then checked.
 const o=verifyBody(graph,4,[
  '20:0 45 4 41:0 f b 20:0 41:4 4b 4 41:0 f b 20:1 45 4 41:0 f b',
  '41:16 20:0 41:1 6b 41:32 6c 6a 21:2',
  '20:2 28:20 41:1 47 4 41:0 f b 20:2 28:16 20:1 47 4 41:0 f b',
  '20:2 28:12 20:2 28:4 4b 4 41:0 f b',
  '41:144 28:0 20:5 71 20:5 47 4 41:0 f b'
 ]);if(o.some(x=>x.startsWith('36:')))throw Error('owner verifier writes');
 const prefix=(owner,desc,base)=>`20:0 20:1 10:4 21:${owner} 20:${owner} 45 4 41:-4 f b 41:${base} 20:0 41:1 6b 41:16 6c 6a 21:${desc}`;
 // Checks dominate the first owner/descriptor writes on the straight-line
 // success edge; negative branches return before those writes.
 verifyBody(graph,5,[prefix(3,4,256),
  '20:4 28:0 45 45 20:4 28:4 20:1 46 71 4 41:-4 f b',
  '20:3 28:12 45 45 4 41:-4 f b',
  '20:2 41:268435455 4b 4 41:-1 f b',
  '20:2 41:16 6c 21:5 20:5 20:3 28:4 4b 4 41:-2 f b'
 ],true);
 verifyBody(graph,6,[prefix(2,3,256),
  '20:3 28:0 41:1 47 4 41:-4 f b 20:3 28:4 20:1 47 4 41:-4 f b',
  '20:4 41:268435455 4b 4 41:-4 f b 20:4 41:16 6c 20:2 28:12 47 4 41:-4 f b',
  '20:4 45 4 20:3 28:8 45 45 4 41:-4 f b 5 20:3 28:8 20:2 28:0 47 4 41:-4 f b b'
 ],true);
 verifyBody(graph,8,[prefix(3,4,320),
  '20:4 28:0 45 45 20:4 28:4 20:1 46 71 4 41:-4 f b',
  '20:2 41:536870911 4b 4 41:-1 f b 20:2 41:8 6c 21:6',
  '20:5 20:3 28:4 4b 4 41:-2 f b 20:6 20:3 28:4 20:5 6b 4b 4 41:-2 f b'
 ],true);
 // Project preflights the two same-owner descriptors, both extents, their
 // non-overlap and n<=capacity before the single worker call.
 const p=verifyBody(graph,9,[
  '20:0 20:1 10:4 21:5 20:5 45 4 41:-4 f b 20:2 20:3 10:4 21:6 20:6 45 4 41:-4 f b 20:0 20:2 47 4 41:-4 f b',
  '20:7 28:0 41:2 47 4 41:-4 f b 20:7 28:4 20:1 47 4 41:-4 f b',
  '20:9 41:268435455 4b 4 41:-4 f b 20:9 41:16 6c 20:5 28:12 4b 4 41:-4 f b',
  '20:8 28:0 41:1 47 4 41:-4 f b 20:8 28:4 20:3 47 4 41:-4 f b 20:8 28:12 45 45 4 41:-4 f b',
  '20:10 41:536870911 4b 4 41:-4 f b 20:10 41:8 6c 21:12',
  '20:13 20:6 28:0 49 4 41:-4 f b',
  '20:11 41:3 71 45 45 4 41:-4 f b 20:11 20:6 28:12 4b 4 41:-4 f b 20:12 20:6 28:12 20:11 6b 4b 4 41:-4 f b',
  '20:9 45 45 20:12 45 45 71 4 20:11 20:9 41:16 6c 49 4 41:-4 f b b',
  '20:9 20:10 4b 4 41:-3 f b 20:7 28:8 20:9 20:13 20:8 20:10 20:4 10:10'
 ],true);if(p.filter(x=>x==='10:10').length!==1)throw Error('worker calls');
 const close=verifyBody(graph,11,[prefix(2,2,256),
  '20:2 28:0 45 45 20:2 28:4 20:1 46 71 4 41:-4 f b',
  '41:320 20:0 41:1 6b 41:16 6c 6a 21:2 20:2 28:0 45 45 20:2 28:4 20:1 46 71 4 41:-4 f b 20:0 20:1 10:1'
 ]);if(close.filter(x=>x==='10:1').length!==1)throw Error('close count');
 verifyBody(graph,12,[prefix(2,2,256),'20:2 28:4 20:1 47 4 41:-4 f b 20:2 28:0 41:2 47 4 41:-4 f b 20:2 41:0 36:0']);
 verifyBody(graph,13,[prefix(2,2,320),'20:2 28:4 20:1 47 4 41:-4 f b 20:2 28:0 41:1 46 20:2 28:0 41:2 46 72 45 4 41:-4 f b 20:2 41:0 36:0']);
 return true;
 } catch {return false;}
}
