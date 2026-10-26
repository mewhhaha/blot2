// Private concrete scalar-array copy-bridge fixture contract. Its caller must
// independently own the manifest, source, callable identity, effects, ABI and
// package root. The source is the restricted checked generic identity body;
// lifting that body to one array invocation is trusted fixture adapter code,
// not a source-checked M12 callable. No complete K1 ABI is asserted.
namespace wire_contract;
import host_bridge;
import generic_identity;
import generic_dictionary;
struct Contract {
    manifest:host_bridge::Manifest=host_bridge::Manifest {},
    fields:host_bridge::Field[8]=[host_bridge::Field {};8], field_count:u32=0,
    predicates:host_bridge::Predicate[8]=[host_bridge::Predicate {};8], predicate_count:u32=0,
    selected:u32=0, alias_result:bool=false
}
struct Spec {source:u8[]=[],body:generic_identity::Body=generic_identity::Body {},contract:Contract=Contract {},dictionary:generic_dictionary::Result=generic_dictionary::Result {}}
struct Result {status:i64=1,spec:Spec=Spec {}}
fn identity(kind:u32) -> u8[:] {
    if kind==0 {return "fixture/unit";} if kind==1 {return "fixture/u32";}
    if kind==2 {return "fixture/f32";} if kind==3 {return "fixture/bool";} return "";
}
fn dictionary(kind:u32) -> generic_dictionary::Result {
    if kind>3 {return generic_dictionary::Result {};}
    var schema=generic_dictionary::Schema {kind:if kind==0 {0} else {1},words:if kind==0 {0} else {1},producer:identity(kind)};
    return generic_dictionary::make(schema,kind+1);
}
fn shape(c:Contract&) -> bool {
    if c.field_count>8 || c.predicate_count>8 || c.selected>=c.field_count ||
       c.manifest.ingress_bytes!=256 || c.manifest.egress_bytes!=256 || c.manifest.work_bytes>512 ||
       c.manifest.output_capacity>16 || c.manifest.result_max_count>16 {return false;}
    for i in c.field_count {if c.fields[i].role==1 && c.fields[i].max_count>16 {return false;}}
    let chosen=c.fields[c.selected];
    if chosen.role!=1 || chosen.kind!=c.manifest.output_kind || chosen.max_count>c.manifest.result_max_count ||
       (!c.alias_result && chosen.max_count>c.manifest.output_capacity) {return false;}
    let _,_,ok=host_bridge::schema(c.manifest,c.fields[..c.field_count],c.predicates[..c.predicate_count]);
    return ok;
}
fn make(source:u8[:],c:Contract&) -> Result {
    if source.len>4096 || !shape(c) {return Result {};}
    let body=generic_identity::parse(source);if body.status!=0 {return Result {};}
    return Result {status:0,spec:Spec {source:source,body:body,contract:c,dictionary:dictionary(c.manifest.output_kind)}};
}
