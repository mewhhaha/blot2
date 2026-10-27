// Private source and actual-target binding for four concrete builtin schemas.
// Not complete ABI, public admission, package authentication, C09 or M13.
namespace abi_primitive_link;
import abi_primitive_schema;
import abi_primitive_check;
import abi_overload_policy;
import abi_overload_gaps;
import blake3;
import generic_identity;
import generic_identity_verify;
import generic_dictionary;
import generic_dictionary_verify;
import generic_identity_wasm;
import generic_identity_wasm_verify;
struct Candidate {status:i64=1,source:u8[]=[],schema:u8[]=[],dictionary:generic_dictionary::Result=generic_dictionary::Result {},target:u8[]=[],policy_hash:u8[32]=[0;32]}
fn dict(code:u32)->generic_dictionary::Result {
 if code<1 || code>4{return generic_dictionary::Result {};}
 let name=if code==1 {"builtin:Unit"} else if code==2 {"builtin:U32"} else if code==3 {"builtin:F32"} else {"builtin:Bool"};
 var s=generic_dictionary::Schema {kind:if code==1 {0} else {1},words:if code==1 {0} else {1},producer:name};return generic_dictionary::make(s,code);
}
fn verify(c:Candidate&,source:u8[:],code:u32)->bool {
 if c.status!=0 || c.source[..]!=source || !abi_primitive_check::verify(c.schema,code){return false;}
 let policy=abi_overload_policy::canonical();if policy.len==0 || !abi_overload_policy::verify(policy) || abi_overload_gaps::publicly_eligible(policy){return false;}
 let hash=blake3::hash(policy);if c.policy_hash[..]!=hash[..]{return false;}
 let body=generic_identity::parse(source);if body.status!=0 || !generic_identity_verify::verify(source,body){return false;}
 var expected=dict(code);if expected.status!=0 || !generic_dictionary_verify::verify(c.dictionary,expected.schema,code){return false;}
 return generic_identity_wasm_verify::verify_linked(source,body,c.dictionary,expected.schema,code,c.target);
}
fn make(source:u8[:],code:u32)->Candidate {
 let schema=abi_primitive_schema::canonical(code);if !abi_primitive_check::verify(schema,code){return Candidate {};}
 let policy=abi_overload_policy::canonical();if policy.len==0 || !abi_overload_policy::verify(policy) || abi_overload_gaps::publicly_eligible(policy){return Candidate {};}
 let body=generic_identity::parse(source);if body.status!=0 || !generic_identity_verify::verify(source,body){return Candidate {};}
 var dictionary=dict(code);if dictionary.status!=0{return Candidate {};}
 let target=generic_identity_wasm::emit(source,body,dictionary,dictionary.schema,code);if target.len==0{return Candidate {};}
 var src:u8[>..]=[];src.append(source);var out=Candidate {status:0,source:copy(src),schema:copy(schema),dictionary:copy(dictionary),target:copy(target),policy_hash:blake3::hash(policy)};
 if !verify(out,source,code){return Candidate {};}
 return out;
}
fn public_eligible(c:Candidate&)->bool {let _=c;return false;}
