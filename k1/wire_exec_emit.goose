// Private test fixture linking the existing multi-field wire contract and
// scalar generic identity Wasm. The host adapter performs trusted elementwise
// lifting; this is neither M12 nor a source-owned array callable or loan proof.
import wire_contract;
import wire_validate;
import generic_identity_wasm;
import generic_identity_wasm_verify;
import host_bridge;
import os;
fn contract(selected:u32) -> wire_contract::Contract {
 var c=wire_contract::Contract {field_count:5,selected:selected};
 c.fields[0]=host_bridge::Field {kind:1};
 c.fields[1]=host_bridge::Field {role:1,kind:1,max_count:4,domain_binder:1};
 c.fields[2]=host_bridge::Field {role:1,kind:3,max_count:4,domain_binder:2};
 c.fields[3]=host_bridge::Field {role:1,kind:2,max_count:4,domain_binder:3};
 c.fields[4]=host_bridge::Field {role:1,kind:0,max_count:4,domain_binder:4};
 c.manifest=host_bridge::Manifest {export_id:27,ingress_bytes:256,egress_bytes:256,output_kind:c.fields[selected].kind,
 output_capacity:4,result_max_count:4,required_domain_mask:15,work_bytes:64,output_items_are_count:true};
 return c;
}
fn main() {
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 for selected in 1..5 {
  var c=contract(selected as u32);var made=wire_contract::make(source,c);
  assert(made.status==0 && wire_validate::verify(made.spec,source,c));
  let schema=wire_validate::expected_dictionary(c.manifest.output_kind);
  let bytes=generic_identity_wasm::emit(source,made.spec.body,made.spec.dictionary,schema,c.manifest.output_kind+1);
  assert(bytes.len>0 && generic_identity_wasm_verify::verify_linked(source,made.spec.body,made.spec.dictionary,schema,c.manifest.output_kind+1,bytes));
  var wrong=c;wrong.fields[1].max_count=3;assert(!wire_validate::verify(made.spec,source,wrong));
  assert(!wire_validate::verify(made.spec,"wrong",c));
  for i in bytes.len {var bad:u8[>..]=[];bad.append(bytes);bad[i]^=1;assert(!generic_identity_wasm_verify::verify_linked(source,made.spec.body,made.spec.dictionary,schema,c.manifest.output_kind+1,bad));}
  let path=if selected==1 {"wire-exec-u32.wasm"} else if selected==2 {"wire-exec-bool.wasm"} else if selected==3 {"wire-exec-f32.wasm"} else {"wire-exec-unit.wasm"};
  assert(write_file(path,bytes));
 }
 print("private multi-schema wire source/manifest/identity target binding passed");
}
