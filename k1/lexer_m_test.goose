import lexer;
import lexer_m;
import work;
fn compare(source:u8[:]) {
 var a=lexer::init(source);var b=lexer_m::init(source,work::Meter {});
 for _ in 1024 {
  let x=lexer::next(source,a);let y=lexer_m::next(source,b);
  assert(x.kind==y.kind && x.start==y.start && x.end==y.end && x.status==y.status);
  if x.kind==0 || x.kind==9 {return;}
 }
 abort("unexpected lexer length");
}
fn main() {
 for s in ["", "static let x: U32 = 1+2\n", "let f = do:\n  return #[1,2]\n", "// comment\n(a,\n  1.5)\n", "a\r\nb\n", "(]", "x 4294967296", "\"escaped\\\"name\""] {compare(s);}
 let utf:u8[3]=[0xe2,0x82,0xac];compare(utf);let bad:u8[2]=[0xc2,0x20];compare(bad);
 var m=lexer_m::init("x",work::Meter {source_byte_reads:~(0 as u64)});assert(m.work_status==6 && m.meter.source_byte_reads==~(0 as u64));
 let t=lexer_m::next("x",m);assert(t.kind==9 && t.status==6);
 var invalid=lexer_m::init("x",work::Meter {gate:8});assert(invalid.work_status==5 && lexer_m::next("x",invalid).kind==9);
 var too_long:u8[>..]=[32;16777217];var size=lexer_m::init(too_long,work::Meter {});assert(size.meter.source_byte_reads==0 && lexer_m::next(too_long,size).status==5);
 print("metered lexer differential and pre-read telemetry passed");
}
