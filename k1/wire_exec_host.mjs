// Private test adapter: four fixed, compiler-checked manifests; the scalar
// identity body is lifted elementwise in trusted JS. No K1 public ABI, Wasm
// invocation region, source-owned array callable or general loan cleanup.
const exact = Uint8Array.from([
  0,97,115,109,1,0,0,0,1,8,1,96,4,127,127,127,127,0,3,2,1,0,5,4,1,1,1,1,
  7,21,2,6,109,101,109,111,114,121,2,0,8,105,100,101,110,116,105,116,121,0,0,
  10,17,1,15,0,32,1,32,3,32,2,40,2,0,252,10,0,0,11]);
const typedLength = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),'length').get;
const uint = x => Number.isInteger(x) && x >= 0 && x <= 0xffffffff;
function snapshot(values,check) {
  if (!Array.isArray(values)) throw new TypeError('expected array');
  const len=Object.getOwnPropertyDescriptor(values,'length');
  if (!len || !('value' in len) || !uint(len.value) || len.value>4) throw new TypeError('invalid length');
  const out=[];
  for(let i=0;i<len.value;i++) {
    const d=Object.getOwnPropertyDescriptor(values,String(i));
    if(!d || !('value' in d) || !check(d.value)) throw new TypeError('invalid element');
    out.push(d.value);
  }
  return out;
}
export function createWireExecFixture(bytes,selected) {
  // This independently pins every target byte. `selected` is a trusted
  // fixture choice supplied by the compiler request, not host authority.
  if (!(bytes instanceof Uint8Array) || typedLength.call(bytes)!==exact.length || !Uint8Array.prototype.every.call(bytes,(b,i)=>b===exact[i]) ||
      !Number.isInteger(selected) || selected<1 || selected>4) throw new TypeError('invalid fixture');
  const instance=new WebAssembly.Instance(new WebAssembly.Module(exact));
  const mem=new Uint8Array(instance.exports.memory.buffer), view=new DataView(mem.buffer);
  let running=false, poisoned=false;
  return Object.freeze({call(scalar,u32,bool,f32bits,units,capacity) {
    if(poisoned) return {status:'Poisoned'};
    if(running) return {status:'Busy'};
    running=true;
    try {
      if(!uint(scalar)||!uint(units)||units>4||!uint(capacity)||capacity>224) throw new TypeError('invalid input');
      const arrays=[null,snapshot(u32,uint),snapshot(bool,x=>typeof x==='boolean'),snapshot(f32bits,uint),Array(units).fill(0)];
      const input=arrays[selected], stride=selected===4?0:4, required=8+input.length*stride;
      // All input arrays have been copied and checked before touching Wasm.
      // Each worker call is an independent scalar identity, not one M12 call.
      mem.fill(0);view.setUint32(256,stride,true);
      const result=[];
      for(const value of input) {
        if(stride) view.setUint32(1024,selected===2?(value?1:0):value,true);
        try {instance.exports.identity(0,stride?2048:0,256,stride?1024:0);}
        catch(error) {if(error instanceof WebAssembly.RuntimeError) {poisoned=true;return {status:'Poisoned'};} throw error;}
        result.push(stride?view.getUint32(2048,true):0);
      }
      if(required>capacity) return {status:'OutputTooSmall',required,count:input.length};
      if(selected===2) return {status:'Ok',values:result.map(x=>x!==0)};
      if(selected===4) return {status:'Ok',count:input.length};
      return {status:'Ok',values:Uint32Array.from(result)};
    } finally {mem.fill(0);running=false;}
  }});
}
