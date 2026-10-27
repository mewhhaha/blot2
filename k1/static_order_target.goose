// Independent byte reconstruction of the fixed private module. The caller
// must first verify its image against source; this helper checks geometry and
// target bytes only, not general Wasm or M13 certification.
namespace static_order_target;
import static_publish_core;
import work;
fn u(out:u8[>..]&,v:i64) {var n=v;while n>=128 {out.push(((n%128)+128) as u8);n/=128;}out.push(n as u8);}
fn s32(out:u8[>..]&,v:u32){var n:i64=v;if n>=2147483648 {n-=4294967296;}loop {let b=(n&127) as u8;n=n>>7;if (n==0&&b<64)||(n== -1&&b>=64){out.push(b);break;}out.push(b+128);}}
fn section(out:u8[>..]&,id:u8,b:u8[:]){out.push(id);u(out,b.len);out.append(b);}
fn body(out:u8[>..]&,b:u8[:]){u(out,b.len);out.append(b);}
fn ci(out:u8[>..]&,n:u32){out.push(0x41);s32(out,n);}
fn verify(image:static_publish_core::Image&,candidate:u8[:],w:work::ScheduledWork&)->i64 {
 if image.width<2 || image.width>16 || image.rows<1 || image.bytes>4194304 || image.data.len!=image.bytes || (image.rows as u64)*(image.width as u64)*4!=image.bytes as u64{return 1;}
 let artifact=work::scheduled_charge(w,7,12);if artifact.status!=0{return if artifact.status==1 {4} else {5};}
 var expected:u8[>..]=[0,97,115,109,1,0,0,0];let types:u8[11]=[2,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f];section(expected,1,types);
 let fs:u8[4]=[3,0,1,1];section(expected,3,fs);var mem:u8[>..]=[1,1];let pages=(image.bytes as i64+65535)/65536;u(mem,pages);u(mem,pages);section(expected,5,mem);
 let exp:u8[25]=[3,4,'r','e','a','d',0,0,6,'l','e','n','g','t','h',0,1,5,'w','i','d','t','h',0,2];section(expected,7,exp);
 var code:u8[>..]=[3];var get:u8[>..]=[0,0x20,0];ci(get,image.rows);get.append([0x4f,0x04,0x40,0,0x0b,0x20,1]);ci(get,image.width);
 get.append([0x4f,0x04,0x40,0,0x0b,0x20,0]);ci(get,image.width);get.append([0x6c,0x20,1,0x6a]);ci(get,4);get.append([0x6c,0x28,2,0,0x0b]);body(code,get);
 var a:u8[>..]=[0];ci(a,image.rows);a.push(0x0b);body(code,a);var b:u8[>..]=[0];ci(b,image.width);b.push(0x0b);body(code,b);section(expected,10,code);
 var bytes:u8[>..]=[1,0,0x41,0,0x0b];u(bytes,image.bytes);bytes.append(image.data);section(expected,11,bytes);
 if expected.len!=candidate.len{return 1;}
 for i in expected.len {
  let target=work::target_visit(w.meter);if target.status!=0{return if target.status==6 {6} else {5};}
  if expected[i]!=candidate[i]{return 1;}
 }
 return 0;
}
