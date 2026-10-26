// Private test adapter for compiler-verified bytes. Each opening owns an
// unexported WeakMap of index objects; it models per-instance isolation but
// is not K1's erased Domain type, an authenticated artifact, or public ABI.
export function openVerifiedFixture(bytes) {
 const mod=new WebAssembly.Module(bytes);
 if(WebAssembly.Module.imports(mod).length!==0)throw new TypeError('imports forbidden');
 const exports=WebAssembly.Module.exports(mod);
 if(JSON.stringify(exports.map(x=>[x.name,x.kind]))!==JSON.stringify([['read','function'],['length','function'],['width','function']]))throw new TypeError('unexpected exports');
 const e=new WebAssembly.Instance(mod).exports, length=e.length()>>>0, width=e.width()>>>0, domains=new WeakMap();
 if(length===0||width<2||width>16)throw new TypeError('unsupported geometry');
 return Object.freeze({length,width,
   index(i){if(!Number.isInteger(i)||i<0||i>=length)throw new RangeError('index out of bounds');const k=Object.freeze(Object.create(null));domains.set(k,i);return k;},
   read(index,field){if((typeof index!=='object'&&typeof index!=='function')||index===null||!domains.has(index))throw new TypeError('foreign index');
    if(!Number.isInteger(field)||field<0||field>=width)throw new RangeError('field out of bounds');return e.read(domains.get(index),field)>>>0;}
 });
}
