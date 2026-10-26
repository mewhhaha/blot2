// Independent source, dictionary and caller-owned manifest comparison for the
// private copy-bridge fixture. It cannot authenticate expected source, schema
// IDs, runtime memory or host mapping. Fixed inactive slots are not authority.
namespace wire_validate;
import wire_contract;
import host_bridge;
import generic_identity_verify;
import generic_dictionary_verify;
import public_artifact;
fn same_field(a:host_bridge::Field,b:host_bridge::Field) -> bool {
    return a.role==b.role && a.kind==b.kind && a.max_count==b.max_count && a.nat_binder==b.nat_binder && a.domain_binder==b.domain_binder;
}
fn same_term(a:host_bridge::Term,b:host_bridge::Term) -> bool {return a.kind==b.kind && a.field==b.field && a.literal==b.literal;}
fn same_pred(a:host_bridge::Predicate,b:host_bridge::Predicate) -> bool {return a.kind==b.kind && same_term(a.left,b.left) && same_term(a.right,b.right);}
fn same_manifest(a:host_bridge::Manifest,b:host_bridge::Manifest) -> bool {
    return a.export_id==b.export_id && a.ingress_bytes==b.ingress_bytes && a.egress_bytes==b.egress_bytes &&
        a.expected_items==b.expected_items && a.output_kind==b.output_kind && a.output_capacity==b.output_capacity &&
        a.result_max_count==b.result_max_count && a.output_nat_binder==b.output_nat_binder &&
        a.required_nat_mask==b.required_nat_mask && a.required_domain_mask==b.required_domain_mask &&
        a.work_bytes==b.work_bytes && a.output_items_are_count==b.output_items_are_count;
}
fn same_contract(a:wire_contract::Contract&,b:wire_contract::Contract&) -> bool {
    if a.field_count>8 || b.field_count>8 || a.predicate_count>8 || b.predicate_count>8 ||
       a.field_count!=b.field_count || a.predicate_count!=b.predicate_count || a.selected!=b.selected ||
       a.alias_result!=b.alias_result || !same_manifest(a.manifest,b.manifest) {return false;}
    for i in a.field_count {if !same_field(a.fields[i],b.fields[i]) {return false;}}
    for i in a.predicate_count {if !same_pred(a.predicates[i],b.predicates[i]) {return false;}}
    return true;
}
fn valid_term(t:host_bridge::Term,c:wire_contract::Contract&) -> bool {
    if t.kind>3 {return false;}
    if t.kind==0 {return t.field==0;}
    if t.literal!=0 {return false;}
    if t.kind==3 {return t.field==0;}
    if t.field>=c.field_count {return false;}
    let f=c.fields[t.field];
    if t.kind==1 {return f.role==0 && f.kind==1;}
    return f.role==1;
}
// Independently recompute the bounded schema, binder sets, supported
// predicates and worst placement in wider arithmetic. It shares no producer
// shape result and does not grant semantic type or source authority.
fn shape(c:wire_contract::Contract&) -> bool {
    let m=c.manifest;
    if c.field_count>8 || c.predicate_count>8 || c.selected>=c.field_count ||
       m.ingress_bytes!=256 || m.egress_bytes!=256 || m.work_bytes>512 ||
       m.output_kind>3 || m.output_capacity>16 || m.result_max_count>16 || m.output_nat_binder>32 {return false;}
    var nat:u32=0;var domains:u32=0;var work:u64=0;
    for i in c.field_count {
        let f=c.fields[i];
        if f.kind>3 || f.role>1 || f.nat_binder>32 || f.domain_binder>32 {return false;}
        if f.role==0 {
            if f.max_count!=0 || f.nat_binder!=0 || f.domain_binder!=0 {return false;}
        } else {
            if f.max_count>16 || f.domain_binder==0 {return false;}
            let bit=1 as u32 << (f.domain_binder-1);
            if (domains & bit)!=0 {return false;}domains |= bit;
            if f.nat_binder!=0 {nat |= 1 as u32 << (f.nat_binder-1);}
            if f.kind!=0 {work=(work+3)/4*4+(f.max_count as u64)*4;}
        }
    }
    if m.output_nat_binder!=0 {nat |= 1 as u32 << (m.output_nat_binder-1);}
    if m.output_kind!=0 {work=(work+3)/4*4+(m.output_capacity as u64)*4;}
    if work>m.work_bytes || nat!=m.required_nat_mask || domains!=m.required_domain_mask {return false;}
    let selected=c.fields[c.selected];
    if selected.role!=1 || selected.kind!=m.output_kind || selected.max_count>m.result_max_count ||
       (!c.alias_result && selected.max_count>m.output_capacity) {return false;}
    for i in c.predicate_count {
        let p=c.predicates[i];if p.kind>5 || !valid_term(p.left,c) || !valid_term(p.right,c) {return false;}
    }
    return true;
}
fn expected_dictionary(kind:u32) -> u8[>..] {
    var out:u8[>..]=[];
    if kind>3 {return out;}
    let producer=if kind==0 {"fixture/unit"} else if kind==1 {"fixture/u32"} else if kind==2 {"fixture/f32"} else {"fixture/bool"};
    out.append("K1GSC001");public_artifact::put32(out,if kind==0 {0} else {1});
    public_artifact::put32(out,if kind==0 {0} else {1});public_artifact::put32(out,producer.len as u32);out.append(producer);return out;
}
fn verify(spec:wire_contract::Spec&,expected_source:u8[:],expected:wire_contract::Contract&) -> bool {
    if expected_source.len>4096 || spec.source[..]!=expected_source || !shape(expected) ||
       !same_contract(spec.contract,expected) || !generic_identity_verify::verify(expected_source,spec.body) {return false;}
    let canonical=expected_dictionary(expected.manifest.output_kind);
    return canonical.len!=0 && generic_dictionary_verify::verify(spec.dictionary,canonical,expected.manifest.output_kind+1);
}
