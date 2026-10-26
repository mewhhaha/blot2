// Private source-order binding. This validates a closed source candidate; the
// separately checked target is still the raw kernel, not adapter ABI lowering.
namespace source_wire_order;
import lexer;
import m12_adapter_core;
import m12_adapter_verify;
fn verify(p:m12_adapter_core::Program&,source:u8[:])->bool {
 if !m12_adapter_verify::verify(p,source) || m12_adapter_verify::public_eligible(p,source) {return false;}
 let body=source[p.split..];var l=lexer::init(body);var prior:i64=0;var got:i64=0;
 // Read the source record's field declarations, not caller-supplied field
 // metadata. The fixed independent adapter recognizer rejects all other forms.
 let names=["source","dt","output"];let types=["View","F32","Dest"];
 var tokens:lexer::Token[>..]=[];loop {let t=lexer::next(body,l);if t.kind==9{return false;}if t.kind==0{break;}
  if tokens.len>=4096{return false;}tokens.push(t);}
 for name,i in names {
  var found:i64=-1;
  for t,j in tokens {if j+2>=tokens.len {break;}let colon=tokens[j+1];let ty=tokens[j+2];
   if t.kind==1 && colon.kind==5 && ty.kind==1 && body[t.start..t.end]==name && body[colon.start..colon.end]==":" && body[ty.start..ty.end]==types[i] {found=t.start;break;}}
  if found<prior || (i>0 && found==prior) {return false;}prior=found;got+=1;
 }
 return got==3;
}
