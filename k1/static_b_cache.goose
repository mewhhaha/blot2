// Source-owned local cache for the instrumented *scalar helper only*. A hit
// replays the exact logical phase-1 and phase-2 visits recorded by the first
// independently verified parse. Other C09 traversals remain uninstrumented.
namespace static_b_cache;
import work;
import static_b_parse;
import static_b_verify;
struct Result {status:i64=1,meter:work::Meter=work::Meter {},completed:u32=0}
fn charge(m:work::Meter&,phase:u32,count:u32)->bool {
 for _ in count {if work::charge(m,phase,1).status!=0{return false;}}return true;
}
fn run(source:u8[:],repetitions:u32,seed:u32,byte_seed:u64,cached:bool)->Result {
 if repetitions==0 || repetitions>100000 || seed>1048576{return Result {};}
 var meter=work::Meter {semantic:seed,source_byte_reads:byte_seed};var seen:bool=false;var parse_visits:u32=0;var verify_visits:u32=0;var done:u32=0;
 for _ in repetitions {
  if cached && seen {
   if !charge(meter,1,parse_visits) || !charge(meter,2,verify_visits){return Result {status:4,meter:meter,completed:done};}
  } else {
   let before=meter.semantic;var parsed=static_b_parse::parse(source,meter);meter=parsed.meter;
   if parsed.status!=0 {return Result {status:parsed.status,meter:meter,completed:done};}
   let after_parse=meter.semantic;let checked=static_b_verify::verify(source,parsed.tree,meter);meter=checked.meter;
   if !checked.ok {return Result {status:if checked.limited {4} else if checked.work_status==6 {6} else if checked.work_status!=0 {5} else {1},meter:meter,completed:done};}
   if !seen {parse_visits=after_parse-before;verify_visits=meter.semantic-after_parse;seen=true;}
  }
  done+=1;
 }
 return Result {status:0,meter:meter,completed:done};
}
