// Actual fixed-target construction with ordered per-node/edge charges and
// target-byte telemetry. Dynamic allocator internals are not a C09 receipt.
namespace static_ot_emit;
import work;
import static_publish_core;
import static_ot_core;
struct State {status:i64=0}
fn event(w:work::ScheduledWork&,s:State&,kind:u32) {if s.status!=0{return;}let q=work::scheduled_charge(w,7,kind);if q.status!=0 {s.status=if q.status==1 {4} else {5};}}
fn tick(w:work::ScheduledWork&,s:State&) {if s.status!=0{return;}let q=work::target_visit(w.meter);if q.status!=0 {w.failed=true;s.status=if q.status==6 {6} else {5};}}
fn put(o:u8[>..]&,w:work::ScheduledWork&,s:State&,b:u8) {tick(w,s);if s.status==0{o.push(b);}}
fn fixed(o:u8[>..]&,w:work::ScheduledWork&,s:State&,data:u8[:]) {for i in data.len {tick(w,s);if s.status!=0{return;}o.push(data[i]);}}
fn bytes(o:u8[>..]&,w:work::ScheduledWork&,s:State&,data:u8[:]) {for i in data.len {tick(w,s);if s.status!=0{return;}let b=data[i];put(o,w,s,b);if s.status!=0{return;}}}
fn u(o:u8[>..]&,w:work::ScheduledWork&,s:State&,v:i64){var n=v;while n>=128 && s.status==0 {put(o,w,s,((n%128)+128) as u8);n/=128;}put(o,w,s,n as u8);}
fn si(o:u8[>..]&,w:work::ScheduledWork&,s:State&,v:u32){var n:i64=v;if n>=2147483648 {n-=4294967296;}loop {if s.status!=0{return;}let b=(n&127) as u8;n=n>>7;if (n==0&&b<64)||(n== -1&&b>=64){put(o,w,s,b);break;}put(o,w,s,b+128);}}
fn section(o:u8[>..]&,w:work::ScheduledWork&,s:State&,id:u8,p:u8[:]) {event(w,s,12);event(w,s,13);put(o,w,s,id);u(o,w,s,p.len);bytes(o,w,s,p);}
fn body(o:u8[>..]&,w:work::ScheduledWork&,s:State&,p:u8[:]) {event(w,s,13);u(o,w,s,p.len);bytes(o,w,s,p);}
fn ins(o:u8[>..]&,w:work::ScheduledWork&,s:State&,op:u8) {event(w,s,13);event(w,s,12);put(o,w,s,op);}
fn iu(o:u8[>..]&,w:work::ScheduledWork&,s:State&,op:u8,n:i64) {ins(o,w,s,op);u(o,w,s,n);}
fn ci(o:u8[>..]&,w:work::ScheduledWork&,s:State&,n:u32) {ins(o,w,s,0x41);si(o,w,s,n);}
fn export_fn(o:u8[>..]&,w:work::ScheduledWork&,s:State&,name:u8[:],id:i64){event(w,s,13);event(w,s,12);u(o,w,s,name.len);fixed(o,w,s,name);put(o,w,s,0);u(o,w,s,id);}
fn emit(image:static_publish_core::Image&,w:work::ScheduledWork&)->static_ot_core::Bytes {
 var s=State {};event(w,s,10);if s.status!=0{return static_ot_core::Bytes {status:s.status};}
 if image.width<2 || image.width>16 || image.rows<1 || image.bytes>4194304 || image.data.len!=image.bytes || (image.rows as u64)*(image.width as u64)*4!=image.bytes as u64{return static_ot_core::Bytes {};}
 event(w,s,10);var out:u8[>..]=[];fixed(out,w,s,[0,97,115,109,1,0,0,0]);
 event(w,s,10);event(w,s,12);var types:u8[>..]=[];put(types,w,s,2);event(w,s,12);fixed(types,w,s,[0x60,2,0x7f,0x7f,1,0x7f]);event(w,s,12);fixed(types,w,s,[0x60,0,1,0x7f]);section(out,w,s,1,types);
 event(w,s,10);event(w,s,12);var funcs:u8[>..]=[];put(funcs,w,s,3);for typ in [0,1,1] {event(w,s,13);u(funcs,w,s,typ);}section(out,w,s,3,funcs);
 event(w,s,10);event(w,s,12);var mem:u8[>..]=[];fixed(mem,w,s,[1,1]);let pages=(image.bytes as i64+65535)/65536;u(mem,w,s,pages);u(mem,w,s,pages);section(out,w,s,5,mem);
 event(w,s,10);event(w,s,12);var exports:u8[>..]=[];put(exports,w,s,3);export_fn(exports,w,s,"read",0);export_fn(exports,w,s,"length",1);export_fn(exports,w,s,"width",2);section(out,w,s,7,exports);
 event(w,s,10);event(w,s,12);var code:u8[>..]=[];put(code,w,s,3);event(w,s,10);event(w,s,12);var read:u8[>..]=[];put(read,w,s,0);
 iu(read,w,s,0x20,0);ci(read,w,s,image.rows);ins(read,w,s,0x4f);ins(read,w,s,0x04);put(read,w,s,0x40);ins(read,w,s,0);ins(read,w,s,0x0b);
 iu(read,w,s,0x20,1);ci(read,w,s,image.width);ins(read,w,s,0x4f);ins(read,w,s,0x04);put(read,w,s,0x40);ins(read,w,s,0);ins(read,w,s,0x0b);
 iu(read,w,s,0x20,0);ci(read,w,s,image.width);ins(read,w,s,0x6c);iu(read,w,s,0x20,1);ins(read,w,s,0x6a);ci(read,w,s,4);ins(read,w,s,0x6c);
 ins(read,w,s,0x28);put(read,w,s,2);put(read,w,s,0);ins(read,w,s,0x0b);body(code,w,s,read);
 event(w,s,10);event(w,s,12);var count:u8[>..]=[];put(count,w,s,0);ci(count,w,s,image.rows);ins(count,w,s,0x0b);body(code,w,s,count);
 event(w,s,10);event(w,s,12);var width:u8[>..]=[];put(width,w,s,0);ci(width,w,s,image.width);ins(width,w,s,0x0b);body(code,w,s,width);section(out,w,s,10,code);
 event(w,s,10);event(w,s,12);var data:u8[>..]=[];fixed(data,w,s,[1,0]);ci(data,w,s,0);ins(data,w,s,0x0b);u(data,w,s,image.bytes);bytes(data,w,s,image.data);section(out,w,s,11,data);
 if s.status!=0{return static_ot_core::Bytes {status:s.status};}return static_ot_core::Bytes {status:0,bytes:out};
}
