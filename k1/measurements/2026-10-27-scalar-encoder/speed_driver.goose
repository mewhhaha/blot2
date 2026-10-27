import std;
import os;
import scalar_scheduled;
import work;
fn main() {
 let argv=args();if argv.len!=3 {exit(2);}
 var source:u8[>..]=[];if !read_file(argv[1],source) {exit(3);}
 let loops=if argv[2]=="short" {2000} else if argv[2]=="medium" {100} else if argv[2]=="long" || argv[2]=="dense" || argv[2]=="mixed" || argv[2]=="name" {4} else {0};
 if loops==0 {exit(4);}
 var sum:u64=0;var visits:u32=0;var target:u64=0;var first_len:i64=0;
 for i in loops {
  var w=work::ScheduledWork {};let r=scalar_scheduled::run(source,w);
  if r.status!=0 || !work::schedule_complete(w) {exit(5);}
  if i==0 {visits=w.meter.semantic;target=w.meter.target_visits;first_len=r.bytes.len;}
  else if visits!=w.meter.semantic || target!=w.meter.target_visits || first_len!=r.bytes.len {exit(6);}
  for b in r.bytes {sum+=b;}
 }
 print("iterations:",loops," semantic:",visits," target:",target," output_length:",first_len," byte_sum:",sum);
}
