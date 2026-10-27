// Independent bounded decoder for exactly one private static-data target. It
// charges semantic target nodes/edges and target-byte inspections before the
// covered work. It is not a general Wasm validator or a full C09 certificate.
namespace static_ot_check;
import work;
import static_publish_core;
struct Reader {pos:i64=0,limit:i64=0,status:i64=0}
fn node(w:work::ScheduledWork&,r:Reader&) {if r.status!=0{return;}let edge=work::scheduled_charge(w,7,13);if edge.status!=0 {r.status=if edge.status==1 {4} else {5};return;}
 let visit=work::scheduled_charge(w,7,12);if visit.status!=0 {r.status=if visit.status==1 {4} else {5};}}
fn byte(bytes:u8[:],w:work::ScheduledWork&,r:Reader&)->u8 {
 if r.status!=0{return 0;}if r.pos<0 || r.pos>=r.limit || r.limit>bytes.len {r.status=1;return 0;}
 let visit=work::target_visit(w.meter);if visit.status!=0 {w.failed=true;r.status=if visit.status==6 {6} else {5};return 0;}
 let b=bytes[r.pos];r.pos+=1;return b;
}
fn need(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,v:u8) {let b=byte(bytes,w,r);if r.status==0 && b!=v {r.status=1;}}
fn u(bytes:u8[:],w:work::ScheduledWork&,r:Reader&)->i64 {
 var value:u64=0;var shift:i64=0;var count:i64=0;
 loop {if r.status!=0 || count>=5 {if r.status==0 {r.status=1;}return 0;}
  let b=byte(bytes,w,r);count+=1;if r.status!=0{return 0;}if count==5 && (b&0xf0)!=0 {r.status=1;return 0;}
  value|=(b&127) as u64 << shift;if (b&128)==0 {if count>1 && (b&127)==0 {r.status=1;}return value as i64;}shift+=7;
 }
}
fn uexpect(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,v:i64){let n=u(bytes,w,r);if r.status==0 && n!=v {r.status=1;}}
fn raw(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,v:u8[:]){for b in v {need(bytes,w,r,b);if r.status!=0{return;}}}
fn section(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,id:u8)->i64 {
 node(w,r);need(bytes,w,r,id);let len=u(bytes,w,r);
 if r.status!=0 || len<0 || len>r.limit-r.pos {if r.status==0 {r.status=1;}return 0;}let end=r.pos+len;r.limit=end;return end;
}
fn local(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,i:i64){node(w,r);need(bytes,w,r,0x20);uexpect(bytes,w,r,i);}
fn op(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,v:u8){node(w,r);need(bytes,w,r,v);}
fn constant(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,v:u32){node(w,r);need(bytes,w,r,0x41);var n:i64=v;if n>=2147483648 {n-=4294967296;}
 loop {let b=(n&127) as u8;n=n>>7;if (n==0&&b<64)||(n== -1&&b>=64){need(bytes,w,r,b);break;}need(bytes,w,r,b+128);if r.status!=0{return;}}
}
fn export_fn(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,name:u8[:],id:i64){node(w,r);uexpect(bytes,w,r,name.len);raw(bytes,w,r,name);need(bytes,w,r,0);uexpect(bytes,w,r,id);}
fn body_end(bytes:u8[:],w:work::ScheduledWork&,r:Reader&,section_end:i64)->i64 {node(w,r);let n=u(bytes,w,r);if r.status!=0 || n<0 || n>section_end-r.pos {if r.status==0 {r.status=1;}return 0;}let end=r.pos+n;r.limit=end;return end;}
fn finish(r:Reader&,end:i64,parent:i64){if r.status==0 && r.pos!=end {r.status=1;}r.limit=parent;}
fn verify(image:static_publish_core::Image&,candidate:u8[:],w:work::ScheduledWork&)->i64 {
 var r=Reader {limit:candidate.len};node(w,r);
 if image.width<2 || image.width>16 || image.rows<1 || image.bytes>4194304 || image.data.len!=image.bytes || (image.rows as u64)*(image.width as u64)*4!=image.bytes as u64{return if r.status==0 {1} else {r.status};}
 raw(candidate,w,r,[0,97,115,109,1,0,0,0]);
 let types=section(candidate,w,r,1);node(w,r);raw(candidate,w,r,[2,0x60,2,0x7f,0x7f,1,0x7f]);node(w,r);raw(candidate,w,r,[0x60,0,1,0x7f]);finish(r,types,candidate.len);
 let funcs=section(candidate,w,r,3);uexpect(candidate,w,r,3);for v in [0,1,1] {node(w,r);uexpect(candidate,w,r,v);}finish(r,funcs,candidate.len);
 let memory=section(candidate,w,r,5);node(w,r);raw(candidate,w,r,[1,1]);let pages=(image.bytes as i64+65535)/65536;uexpect(candidate,w,r,pages);uexpect(candidate,w,r,pages);finish(r,memory,candidate.len);
 let exports=section(candidate,w,r,7);uexpect(candidate,w,r,3);export_fn(candidate,w,r,"read",0);export_fn(candidate,w,r,"length",1);export_fn(candidate,w,r,"width",2);finish(r,exports,candidate.len);
 let code=section(candidate,w,r,10);uexpect(candidate,w,r,3);let first=body_end(candidate,w,r,code);need(candidate,w,r,0);
 local(candidate,w,r,0);constant(candidate,w,r,image.rows);op(candidate,w,r,0x4f);op(candidate,w,r,0x04);need(candidate,w,r,0x40);op(candidate,w,r,0);op(candidate,w,r,0x0b);
 local(candidate,w,r,1);constant(candidate,w,r,image.width);op(candidate,w,r,0x4f);op(candidate,w,r,0x04);need(candidate,w,r,0x40);op(candidate,w,r,0);op(candidate,w,r,0x0b);
 local(candidate,w,r,0);constant(candidate,w,r,image.width);op(candidate,w,r,0x6c);local(candidate,w,r,1);op(candidate,w,r,0x6a);constant(candidate,w,r,4);op(candidate,w,r,0x6c);
 op(candidate,w,r,0x28);uexpect(candidate,w,r,2);uexpect(candidate,w,r,0);op(candidate,w,r,0x0b);finish(r,first,code);
 let second=body_end(candidate,w,r,code);need(candidate,w,r,0);constant(candidate,w,r,image.rows);op(candidate,w,r,0x0b);finish(r,second,code);
 let third=body_end(candidate,w,r,code);need(candidate,w,r,0);constant(candidate,w,r,image.width);op(candidate,w,r,0x0b);finish(r,third,code);finish(r,code,candidate.len);
 let data=section(candidate,w,r,11);node(w,r);raw(candidate,w,r,[1,0]);constant(candidate,w,r,0);op(candidate,w,r,0x0b);uexpect(candidate,w,r,image.bytes);
 for i in image.data.len {if r.status!=0 {break;}let read=work::target_visit(w.meter);if read.status!=0 {w.failed=true;r.status=if read.status==6 {6} else {5};break;}need(candidate,w,r,image.data[i]);}
 finish(r,data,candidate.len);finish(r,candidate.len,candidate.len);return r.status;
}
