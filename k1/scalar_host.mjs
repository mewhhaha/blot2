// Fixed private fixture host. Pin is tied to separately source-checked target.
// Trusted JS/Wasm intrinsics, private nonconcurrent instance and engine envelope.
const expected=Uint8Array.from(Buffer.from('0061736d01000000010d0260027f7f017f60027f7f017e03030200010506010193029302070a0106696e766f6b6500010a3f020e0020010440410b0f0b412a0f000b2e00200041014b04404280808080100f0b200141024920014180014b7204404280808080200f0b410020001000ad0b00990316626c6f742e6b312e666978747572652e6d656d6f72797b2276657273696f6e223a312c22706167655f6279746573223a36353533362c227061676573223a3237352c226772616e756c655f6279746573223a343039362c227374617469635f6279746573223a302c2264696374696f6e6172795f6279746573223a302c22636f6e74726f6c223a5b302c31365d2c226f776e657273223a5b31362c383139325d2c226f776e65725f736c6f7473223a3235362c226f776e65725f737472696465223a33322c226269746d6170223a5b383230382c3531325d2c226672616d65223a5b383732302c313034383537365d2c22696e6772657373223a5b313035373239362c36353533365d2c22656772657373223a5b313132323833322c36353533365d2c22616c69676e6d656e745f70616464696e67223a5b313138383336382c333536385d2c22706f6f6c223a5b313139313933362c31363737373231365d2c22706167655f70616464696e67223a5b31373936393135322c35333234385d2c226d656d6f72795f6279746573223a31383032323430307d','hex'));
const typedLength=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
export async function create(target){
 if(!(target instanceof Uint8Array))throw new TypeError('target');let n=typedLength.call(target);if(n!==expected.length)throw new TypeError('target');
 const bytes=new Uint8Array(n);Uint8Array.prototype.set.call(bytes,target);if(!Uint8Array.prototype.every.call(bytes,(v,i)=>v===expected[i]))throw new TypeError('target');
 const {instance}=await WebAssembly.instantiate(bytes);let poisoned=false;
 const u32=x=>typeof x==='number' && Number.isInteger(x) && x>=0 && x<=0xffffffff;
 return Object.freeze({invoke(value,depth){
  if(poisoned)return {status:'Poisoned'};
  if(!u32(value) || value>1)return {status:'InvalidInput'};
  if(!u32(depth))return {status:'DepthLimit'};
  try{let r=instance.exports.invoke(value,depth);let status=Number(r>>32n),result=Number(r&0xffffffffn);
   if(status===0)return {status:'Ok',value:result};if(status===1)return {status:'InvalidInput'};if(status===2)return {status:'DepthLimit'};poisoned=true;return {status:'Poisoned'};
  }catch{poisoned=true;return {status:'Poisoned'};}
 }});
}
