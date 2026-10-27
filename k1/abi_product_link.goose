// Private source-linked U32 tuple dictionary/target integration. Input type,
// dictionary bytes/loans and target memory remain trusted caller obligations.
namespace abi_product_link;
import abi_product_schema;
import abi_product_check;
import abi_overload_policy;
import abi_overload_gaps;
import generic_identity;
import generic_identity_verify;
import generic_dictionary;
import generic_dictionary_verify;
import generic_identity_wasm;
import generic_identity_wasm_verify;
import blake3;
struct Candidate {status:i64=1,source:u8[]=[],type_source:u8[]=[],schema:u8[]=[],dictionary:generic_dictionary::Result=generic_dictionary::Result {},target:u8[]=[],policy_hash:u8[32]=[0;32]}
fn dictionary(type_source:u8[:],id:u32)->generic_dictionary::Result {
 let n=abi_product_check::count(type_source);if n<2 || n>16 || id==0{return generic_dictionary::Result {};}
 var s=generic_dictionary::Schema {kind:2,words:n as u32,producer:"builtin:flat-U32-product"};return generic_dictionary::make(s,id);
}
fn verify(c:Candidate&,source:u8[:],type_source:u8[:],id:u32)->bool {
 if c.status!=0 || c.source[..]!=source || c.type_source[..]!=type_source || !abi_product_check::verify(type_source,c.schema) {return false;}
 let policy=abi_overload_policy::canonical();if policy.len==0 || !abi_overload_policy::verify(policy) || abi_overload_gaps::publicly_eligible(policy){return false;}
 let hash=blake3::hash(policy);if hash[..]!=c.policy_hash[..]{return false;}
 let body=generic_identity::parse(source);if body.status!=0 || !generic_identity_verify::verify(source,body){return false;}
 var expected=dictionary(type_source,id);if expected.status!=0 || !generic_dictionary_verify::verify(c.dictionary,expected.schema,id){return false;}
 return generic_identity_wasm_verify::verify_linked(source,body,c.dictionary,expected.schema,id,c.target);
}
fn make(source:u8[:],type_source:u8[:],id:u32)->Candidate {
 let schema=abi_product_schema::canonical(type_source);if !abi_product_check::verify(type_source,schema) {return Candidate {};}
 let policy=abi_overload_policy::canonical();if policy.len==0 || !abi_overload_policy::verify(policy) || abi_overload_gaps::publicly_eligible(policy){return Candidate {};}
 let body=generic_identity::parse(source);if body.status!=0 || !generic_identity_verify::verify(source,body){return Candidate {};}
 var dict=dictionary(type_source,id);if dict.status!=0{return Candidate {};}
 let target=generic_identity_wasm::emit(source,body,dict,dict.schema,id);if target.len==0{return Candidate {};}
 var a:u8[>..]=[];a.append(source);var b:u8[>..]=[];b.append(type_source);
 var c=Candidate {status:0,source:copy(a),type_source:copy(b),schema:copy(schema),dictionary:copy(dict),target:copy(target),policy_hash:blake3::hash(policy)};
 if !verify(c,source,type_source,id){return Candidate {};}return c;
}
fn public_eligible(c:Candidate&)->bool {let _=c;return false;}
