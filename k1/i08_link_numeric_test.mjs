// Independent numerical/state oracle for structured private particle workers.
// It is not a public K1 ABI, ownership proof, general compiler or M13 cert.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
const f=Math.fround;
function make(name) {
  const bytes=readFileSync(name);assert(WebAssembly.validate(bytes));const mod=new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[
    ['reserve','function'],['close','function'],['input_alloc','function'],['input_freeze','function'],
    ['advance','function'],['builder_alloc','function'],['project','function'],['memory','memory'],
  ]);
  const e=new WebAssembly.Instance(mod).exports;assert.throws(()=>e.memory.grow(1),RangeError);return e;
}
function words(e){return new Uint32Array(e.memory.buffer);}
function slot(e,id){return Array.from(words(e).slice(4+(id-1)*8,12+(id-1)*8));}
function desc(e,id,base){return Array.from(words(e).slice(base+(id-1)*4,base+id*4));}
function image(e){return Buffer.from(new Uint8Array(e.memory.buffer));}
function expectedBits(value){const d=new DataView(new ArrayBuffer(4));d.setFloat32(0,value,true);return d.getUint32(0,true);}
function same(got,want){if(Number.isNaN(want))assert(Number.isNaN(new DataView(Uint32Array.of(got).buffer).getFloat32(0,true)));else assert.equal(got>>>0,expectedBits(want)>>>0);}
function setup(e,rows,capacity,pad=0,raw=false) {
  assert.equal(e.reserve(rows.length*16),1);assert.equal(e.reserve(pad+capacity*8),2);
  assert.equal(e.input_alloc(1,1,rows.length),0);const inBase=desc(e,1,64)[2],view=new DataView(e.memory.buffer);
  rows.forEach((r,i)=>r.forEach((v,j)=>raw?view.setUint32(inBase+i*16+j*4,v,true):view.setFloat32(inBase+i*16+j*4,v,true)));
  assert.equal(e.input_freeze(1,1),rows.length);assert.equal(e.advance(2,1,pad),0);
  if(pad)new Uint8Array(e.memory.buffer,slot(e,2)[0],pad).fill(0xa5);
  assert.equal(e.builder_alloc(2,1,capacity),0);return {input:inBase,output:desc(e,2,80)[2],top:slot(e,2)[3]};
}
function numerical(name,rows,dt,fx,fy,pad=0) {
  const e=make(name),prepared=setup(e,rows,rows.length,pad),beforeInput=Buffer.from(new Uint8Array(e.memory.buffer,prepared.input,rows.length*16));
  const beforePad=Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],pad));
  assert.equal(e.project(1,1,2,1,dt),rows.length);assert.equal(slot(e,2)[3],prepared.top);
  assert.deepEqual(desc(e,2,80),[2,1,rows.length?prepared.output:0,rows.length]);
  const v=new DataView(e.memory.buffer),step=f(dt);
  rows.forEach((row,i)=>{const [x,y,vx,vy]=row.map(f);same(v.getUint32(prepared.output+i*8,true),fx(x,y,vx,vy,step));same(v.getUint32(prepared.output+i*8+4,true),fy(x,y,vx,vy,step));});
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,prepared.input,rows.length*16)),beforeInput);
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],pad)),beforePad);
  assert.equal(e.close(1,1),0);assert.equal(e.close(2,1),0);
}

const formulas = [
[(x,y,vx,vy,dt)=>f(f(dt+f(y+y))*y),(x,y,vx,vy,dt)=>f(f(f(f(dt*dt)*f(vx+vx))*vx)+f(dt*x))],
[(x,y,vx,vy,dt)=>f(f(f(f(y*dt)*f(dt+y))+vy)+f(vx*f(dt*f(vx*dt)))),(x,y,vx,vy,dt)=>f(f(f(f(f(f(f(f(x*x)+f(dt*y))+f(x*x))+f(y+vy))+x)+f(vx*y))+vx)+y)],
[(x,y,vx,vy,dt)=>f(f(f(f(f(x*vx)*f(vy+x))*y)+f(f(x+vy)+f(vx*vy)))+f(y*x)),(x,y,vx,vy,dt)=>f(f(y*f(f(y*vy)+vx))+f(f(f(dt*vy)*x)+f(x+x)))],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>y],
[(x,y,vx,vy,dt)=>f(y*x),(x,y,vx,vy,dt)=>f(f(f(dt+f(dt+vy))+f(vy+y))+f(y*x))],
[(x,y,vx,vy,dt)=>f(vy+f(f(y+f(x+y))*x)),(x,y,vx,vy,dt)=>f(dt*f(f(f(x*vy)+y)*vy))],
[(x,y,vx,vy,dt)=>f(f(f(dt+vx)+vy)+f(f(y*dt)*y)),(x,y,vx,vy,dt)=>f(f(f(vy+y)+f(f(vy*vy)+f(y*dt)))+f(f(x*x)+f(x*y)))],
[(x,y,vx,vy,dt)=>f(f(f(y*f(f(vx*dt)*vy))+f(f(f(vx*x)*vy)*y))+f(f(f(vx*y)+y)+dt)),(x,y,vx,vy,dt)=>f(f(vx*dt)+f(f(f(f(f(dt+x)*f(y+vx))*y)*y)+y))],
[(x,y,vx,vy,dt)=>f(f(f(x*dt)+f(f(y*y)*f(y*y)))*y),(x,y,vx,vy,dt)=>f(f(f(f(f(f(y+x)+f(vx*dt))+x)+y)+dt)+vx)],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>f(x+f(f(f(x+y)*y)*dt))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx+f(dt*vy))+f(vy*dt))*x)+f(y*f(x+vx)))+vy),(x,y,vx,vy,dt)=>f(f(f(f(x*vy)*f(y*vx))*f(f(vx+x)*x))+dt)],
[(x,y,vx,vy,dt)=>f(vx*f(f(vy*dt)+f(f(f(vx+x)*y)+vx))),(x,y,vx,vy,dt)=>f(f(f(f(dt*y)*f(vx*vx))+f(f(vy*x)+f(y*y)))+f(vy*y))],
[(x,y,vx,vy,dt)=>f(y+f(f(f(f(vx*y)*x)*vy)*f(f(dt*f(y+vy))+f(x*dt)))),(x,y,vx,vy,dt)=>f(dt+f(f(y*f(x+dt))*dt))],
[(x,y,vx,vy,dt)=>f(f(y*f(f(vy+dt)*y))*f(f(vx+f(y*y))+f(x+f(dt+y)))),(x,y,vx,vy,dt)=>f(f(f(f(f(dt*y)+f(dt+x))+f(vx+f(vx*vy)))*vy)*f(f(vx+y)+x))],
[(x,y,vx,vy,dt)=>dt,(x,y,vx,vy,dt)=>f(x+f(f(f(x+vy)+f(vy+vy))+f(f(dt*vx)*vy)))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx+f(f(x*x)*x))+vy)+y)+f(x+vx))+dt),(x,y,vx,vy,dt)=>f(f(f(f(f(y*vx)*vy)*dt)*vx)+f(f(x*y)+f(x*y)))],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>f(f(f(f(f(vy*f(y+f(x*dt)))*f(f(vy*y)+vx))*vx)*vx)+x)],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(f(f(f(vy+y)+vy)+f(f(dt+x)+x))*f(f(f(dt+x)*f(y+y))+f(f(dt+vy)+dt))),(x,y,vx,vy,dt)=>vx],
[(x,y,vx,vy,dt)=>f(x+f(x+f(y+f(x*x)))),(x,y,vx,vy,dt)=>f(vy+dt)],
[(x,y,vx,vy,dt)=>f(y+x),(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(f(y*y)*f(f(y+y)+dt)),(x,y,vx,vy,dt)=>f(f(f(f(y*vy)*f(dt*vx))+f(x+f(vy*f(vx+vy))))+f(f(f(f(y*vx)*x)+f(dt*y))+y))],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>f(f(vx*f(vx+vy))+f(f(f(x+f(vx*vx))*y)*dt))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(f(x+f(vy*vx))+f(x*vy))+f(y*dt))+f(vx*vx))+f(f(f(y+x)*y)*y))+dt),(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>f(f(vy*f(vx+f(vy*x)))+f(f(f(dt+dt)+vy)*f(dt+f(vx+y))))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx*x)+dt)+x)*f(f(vx+dt)+vy))*x),(x,y,vx,vy,dt)=>f(x+f(f(f(vy*dt)*f(vx*vx))*f(f(f(vx*dt)+f(vx+vy))+vy)))],
[(x,y,vx,vy,dt)=>y,(x,y,vx,vy,dt)=>f(f(dt*f(f(f(dt+vx)+x)+y))*x)],
[(x,y,vx,vy,dt)=>f(y+f(f(f(dt+dt)*f(dt*x))+f(f(vy+vx)+f(dt+x)))),(x,y,vx,vy,dt)=>f(f(f(x+y)*f(y+f(y*f(vx+y))))+f(vy*dt))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(dt*vx)+f(dt*dt))+f(f(f(x*x)*vy)+dt))+f(f(vx+vx)*dt))+x),(x,y,vx,vy,dt)=>f(f(f(vy*f(y*dt))+f(f(dt*dt)+vy))+f(f(f(x+dt)*vy)*f(f(vy+vy)+vy)))],
[(x,y,vx,vy,dt)=>y,(x,y,vx,vy,dt)=>f(f(f(f(x+y)+f(dt*y))*x)+f(x+f(x*y)))],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(f(f(y+dt)+f(f(y*y)*vy))+f(dt*f(f(vy*vx)+vx))),(x,y,vx,vy,dt)=>f(vx+dt)],
[(x,y,vx,vy,dt)=>f(f(f(f(vx*y)+f(x+y))+f(f(vx+x)+x))*f(x+vy)),(x,y,vx,vy,dt)=>f(f(f(f(f(vx*vy)*dt)*y)+f(y+f(vx*vy)))+f(f(f(y+dt)+y)+x))],
[(x,y,vx,vy,dt)=>f(vx*f(f(x*f(dt*dt))+f(y*f(vx*dt)))),(x,y,vx,vy,dt)=>f(f(f(f(vy+vy)+f(x+vy))*f(vx+f(y*y)))+f(f(f(x*f(y+vy))+dt)+vy))],
[(x,y,vx,vy,dt)=>f(f(f(f(dt*x)+f(f(y+y)*y))+y)+f(f(dt+y)+f(y+x))),(x,y,vx,vy,dt)=>vx],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vy*f(f(vy*vy)+x))*vx)+dt)+y)+f(y*vy)),(x,y,vx,vy,dt)=>f(vy+x)],
[(x,y,vx,vy,dt)=>f(f(f(f(vx+vy)+y)+dt)*f(f(f(dt+x)*x)+dt)),(x,y,vx,vy,dt)=>f(f(f(vx+vy)+y)+f(f(dt+vy)*f(y+vx)))],
[(x,y,vx,vy,dt)=>dt,(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>f(f(f(y*f(vx*vx))+f(vx*vx))+x)],
[(x,y,vx,vy,dt)=>f(vy+f(f(vy*f(dt*vy))+dt)),(x,y,vx,vy,dt)=>f(f(f(f(f(f(f(y*x)*y)+dt)+dt)*f(vx+dt))*x)+f(f(f(y*vy)*x)+x))],
[(x,y,vx,vy,dt)=>f(f(f(f(vx*y)+f(x*dt))*f(y*vx))+f(f(dt*x)*vy)),(x,y,vx,vy,dt)=>f(f(f(y+f(dt*x))+x)+vy)],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>f(f(f(f(vx*f(y+vx))*f(vy*dt))+y)+f(vy*f(f(y*y)+f(vy*dt))))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(x*vy)+f(y*vx))+f(f(y+vy)*f(vy+x)))*f(f(y*x)+vx))+f(f(vx*y)*dt)),(x,y,vx,vy,dt)=>f(f(f(f(x*y)*dt)*f(f(f(vy+y)+y)+y))*f(f(f(vx+vy)+vy)+f(f(x*vy)+f(vx*y))))],
[(x,y,vx,vy,dt)=>f(f(f(vx+f(f(vx*vx)*f(y*y)))+f(vy*dt))+f(f(f(f(vy*x)*vy)*y)+f(f(vy*vx)*vy))),(x,y,vx,vy,dt)=>f(vx+vy)],
[(x,y,vx,vy,dt)=>f(f(f(f(vx*x)*f(f(y*x)+dt))*f(dt*x))+x),(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>f(f(f(f(x*y)*f(vx+y))*y)*f(f(f(y+x)+f(vy+vx))*dt)),(x,y,vx,vy,dt)=>f(f(f(f(dt+f(y*x))+x)+dt)+x)],
[(x,y,vx,vy,dt)=>y,(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>f(y*dt)],
[(x,y,vx,vy,dt)=>f(f(f(f(y*dt)*vy)+f(x*f(dt*f(dt+vx))))+f(f(f(vy*vy)*y)*y)),(x,y,vx,vy,dt)=>f(f(f(f(vx+y)*f(dt*vx))+dt)+f(f(x*f(x+vy))*dt))],
[(x,y,vx,vy,dt)=>f(vx+f(f(dt+f(y*dt))+vy)),(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>f(f(f(dt+f(x*vx))+vx)+vx)],
[(x,y,vx,vy,dt)=>f(y*vx),(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(x*f(vy*f(f(y+dt)+f(y*dt)))),(x,y,vx,vy,dt)=>vx],
[(x,y,vx,vy,dt)=>f(f(x+f(y*f(dt*x)))*f(x*f(f(dt*dt)+f(dt+vx)))),(x,y,vx,vy,dt)=>f(f(f(vx+f(vy*y))+dt)+f(x*y))],
[(x,y,vx,vy,dt)=>f(vy+vx),(x,y,vx,vy,dt)=>f(f(f(f(f(dt*vy)+f(dt*dt))+f(f(dt*vy)*f(vy+dt)))*x)+f(f(x+vy)*vx))],
[(x,y,vx,vy,dt)=>x,(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>f(f(vy*vy)*dt),(x,y,vx,vy,dt)=>f(f(f(f(dt*vy)*f(vx+x))+y)*f(f(f(y+vy)+x)+f(x+f(vy+x))))],
[(x,y,vx,vy,dt)=>f(f(f(f(vy*f(f(f(vx*x)*y)+x))+f(vx*y))+f(y*dt))+vx),(x,y,vx,vy,dt)=>f(f(f(f(dt+f(y+y))+f(x*y))+f(f(x+vy)*f(vy*dt)))+f(f(x+y)*f(dt*x)))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(x*x)*vy)+f(f(dt+vy)+f(vx+vy)))+f(f(vy*x)+y))+f(f(vx*vx)*y)),(x,y,vx,vy,dt)=>f(f(f(x*vx)+f(x*y))*vx)],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>f(f(f(f(dt*f(vx+dt))+f(f(vx*vx)*x))+y)+vx)],
[(x,y,vx,vy,dt)=>f(f(f(x+f(y*dt))+f(f(vx+vx)*vx))+vy),(x,y,vx,vy,dt)=>f(vx*vx)],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx*x)*vx)+dt)*f(dt+f(vx*vx)))*f(f(f(vy+f(vx*x))+vx)+x)),(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>f(f(f(dt*f(vy+dt))+y)+f(f(f(x+y)*vx)*f(f(x+y)*f(vy+y))))],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>f(f(f(f(x*y)*f(dt+vx))+f(f(vy+vy)+f(vx+y)))+f(vx*f(f(vy+vy)*dt)))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx*f(dt*dt))+x)+f(f(f(dt+x)+y)*vx))+vy)+vy),(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vy+vx)*x)*x)*y)*f(f(y+vy)+f(vx*dt))),(x,y,vx,vy,dt)=>f(f(vy*f(x+vx))*f(f(f(dt+y)*dt)+dt))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vx*f(vx+f(dt*dt)))*vy)*vy)+f(f(vx+x)*vx))+vx),(x,y,vx,vy,dt)=>f(f(x+f(f(x+f(dt*dt))*y))+f(dt*f(vy+x)))],
[(x,y,vx,vy,dt)=>f(f(f(dt*f(vx*y))+f(dt*vy))+f(f(vy*f(dt*y))+f(f(vx*dt)+dt))),(x,y,vx,vy,dt)=>f(vx*x)],
[(x,y,vx,vy,dt)=>f(vx+dt),(x,y,vx,vy,dt)=>f(f(f(x*f(vy*vx))*f(f(x+vy)+f(y+dt)))+f(f(dt+dt)*f(f(dt+vy)+f(vx+x))))],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>f(f(f(vy+f(vy*dt))+f(y+x))+vx)],
[(x,y,vx,vy,dt)=>f(f(f(vx+f(f(dt*x)*vy))+y)+f(f(f(y*y)*vy)*x)),(x,y,vx,vy,dt)=>f(y+f(f(f(dt*vy)+vy)*f(f(f(x*dt)+dt)+dt)))],
[(x,y,vx,vy,dt)=>f(f(dt+f(f(x*vx)*x))+f(dt*vx)),(x,y,vx,vy,dt)=>f(f(f(f(vx*vx)*f(y+vy))*y)*f(f(vx+vy)+f(f(vy+dt)*f(y*vx))))],
[(x,y,vx,vy,dt)=>y,(x,y,vx,vy,dt)=>f(f(f(f(f(dt*f(f(f(vy+y)+dt)+dt))+x)+f(x+x))+f(dt+vy))+f(y*dt))],
[(x,y,vx,vy,dt)=>f(f(f(f(f(f(vy*vy)*vy)*dt)+f(vy*f(vy+x)))+dt)+f(dt+f(vy+x))),(x,y,vx,vy,dt)=>f(f(dt*f(f(dt+y)+vy))+vx)],
[(x,y,vx,vy,dt)=>f(f(x+vx)*vx),(x,y,vx,vy,dt)=>f(f(f(f(x+dt)+f(f(f(y*vx)*x)*vx))+f(f(f(x+vy)*f(dt+x))*f(y+y)))+x)],
[(x,y,vx,vy,dt)=>f(f(vx*dt)*dt),(x,y,vx,vy,dt)=>f(vy+x)],
[(x,y,vx,vy,dt)=>f(f(f(f(vy*x)*dt)*vy)+f(vy*f(f(f(x+f(x*vx))+vy)+f(vx*vx)))),(x,y,vx,vy,dt)=>f(f(f(vx+f(vx*y))+f(f(f(f(y*vx)*x)*dt)*vx))+vy)],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vy+y)+dt)*x)+y)+f(f(y+dt)*dt)),(x,y,vx,vy,dt)=>f(f(x+f(f(vy+y)*x))*f(f(f(x*vy)*f(dt*dt))*y))],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>vy,(x,y,vx,vy,dt)=>vy],
[(x,y,vx,vy,dt)=>f(f(f(x*dt)+f(y*dt))+f(dt*f(y+vx))),(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(f(f(f(x+vx)+vy)*y)*f(y+f(f(f(vy+x)+dt)+vx))),(x,y,vx,vy,dt)=>f(f(x*f(f(dt+vy)+vx))*f(f(vy*y)+f(x+x)))],
[(x,y,vx,vy,dt)=>vx,(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>f(f(vx*f(f(f(vx*vx)+x)+y))+f(dt*f(vy*vx))),(x,y,vx,vy,dt)=>dt],
[(x,y,vx,vy,dt)=>f(dt+vx),(x,y,vx,vy,dt)=>f(f(x+f(f(vy*vx)*dt))+dt)],
[(x,y,vx,vy,dt)=>f(dt+f(f(f(f(x+x)*vy)*vx)+vx)),(x,y,vx,vy,dt)=>x],
[(x,y,vx,vy,dt)=>f(f(f(f(f(vy+f(f(y+vy)+vx))+f(x*vy))+vx)+y)+y),(x,y,vx,vy,dt)=>x]];
const rows=[[1,-2,3.5,-4.25],[-0,0,-0,0],[Infinity,-Infinity,0,-0],[1,2,Infinity,-Infinity],[1.0000001192092896,-1,-1.0000001192092896,1.0000001192092896],[1e-35,1e30,-1e-20,-1e25]]; for(let i=0;i<formulas.length;i++){numerical(`audit-${i}.wasm`,rows,0.03125,...formulas[i]);numerical(`audit-${i}.wasm`,rows,-0,...formulas[i]);} console.log(`independent particle F32 oracle: ${formulas.length} expressions`);
