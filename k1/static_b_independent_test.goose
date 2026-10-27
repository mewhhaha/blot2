import lexer;
import lexer_m;
import validate;
import static_m_name;
import work;
fn compare(source:u8[:]) {
 var a=lexer::init(source);var b=lexer_m::init(source,work::Meter {});
 for _ in 512 {let x=lexer::next(source,a);let y=lexer_m::next(source,b);
  assert(x.kind==y.kind && x.start==y.start && x.end==y.end && x.status==y.status);
  if x.kind==0 || x.kind==9{return;}}
 abort("lexer failed to terminate");
}
fn main() {
 let alphabet:u8[]="ab_019. /\r\n\t\"#{}[]():+=!&|<>\\";var rng:u64=3891509;
 for trial in 10000 {
  var s:u8[>..]=[];let count=trial%43;
  for _ in count {rng=(rng*1664525+1013904223)%4294967296;let ch=if trial%3==0 {(rng%256) as u8} else {alphabet[(rng%(alphabet.len as u64)) as i64]};s.push(ch);}
  compare(s);var meter=work::Meter {};let name=static_m_name::check(s,meter);assert(name.work_status==0 && name.valid==validate::name_valid(s));
 }
 for s in ["// utf8: \xe2\x82\xac\nlet x = (1 + 2)\n", "\xf0\x90\x80\x80", "a\r\nb\n"] {
  var baseline=lexer_m::init(s,work::Meter {});loop {let t=lexer_m::next(s,baseline);if t.kind==0 || t.kind==9 {break;}}
  let count=baseline.meter.source_byte_reads;for slack in 0..count {var v=lexer_m::init(s,work::Meter {source_byte_reads:~(0 as u64)-slack});var token=lexer_m::next(s,v);while token.kind!=0 && token.kind!=9 {token=lexer_m::next(s,v);}assert(v.work_status==6 && token.kind==9 && v.meter.source_byte_reads==~(0 as u64));}
 }
 print("independent random lexer/name parity and byte-boundary controls passed");
}
