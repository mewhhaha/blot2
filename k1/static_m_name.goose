// Name validation using the same lexical rules and reserved names, with every
// source-byte inspection charged as source_read telemetry before access.
// Byte telemetry is separate from the semantic-visit ceiling.
namespace static_m_name;
import work;
import validate;
struct Result {valid:bool=false,work_status:u32=0}
fn read(name:u8[:],index:i64,meter:work::Meter&)->u8,u32 {
 let receipt=work::source_read(meter,1);if receipt.status!=0{return 0,receipt.status;}return name[index],0;
}
fn check(name:u8[:],meter:work::Meter&)->Result {
 if name.len==0{return Result {};}
 let first,status=read(name,0,meter);if status!=0{return Result {work_status:status};}
 if !validate::letter(first){return Result {};}
 for i in name.len {let ch,st=read(name,i,meter);if st!=0{return Result {work_status:st};}
  if i>0 && !validate::letter(ch) && !validate::digit(ch){return Result {};}}
 for word in ["_","import","as","pub","let","static","local","type","fn","in","do","return","break","continue",
  "next","stop","seal","abort","if","else","case","for","carry","invariant","forall","exists","where",
  "requires","ensures","on_true","on_false","resources","region","owned","pack","open","space","dest","env",
  "builder","view","index","array","U32","F32","Unit","Bool","RegionOwner","Space","Dest","EnvDest","Builder",
  "View","Index","Fn","Owned","Result","Many","Once","Append","Resize","Type","Region","Nat","Domain","Plain","Share"] {
  if name.len==word.len {
   var same=true;for i in name.len {let ch,st=read(name,i,meter);if st!=0{return Result {work_status:st};}if ch!=word[i] {same=false;break;}}
   if same{return Result {};}
  }
 }
 return Result {valid:true};
}
