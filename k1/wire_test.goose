import wire_contract;
import wire_validate;
import wire_runtime;
import host_bridge;
fn put(b:u8[:],p:i64,x:u32) {for i in 4 {b[p+i]=(x >> (8*i) & 255) as u8;}}
fn get(b:u8[:],p:i64) -> u32 {return b[p] | (b[p+1] as u32 << 8) | (b[p+2] as u32 << 16) | (b[p+3] as u32 << 24);}
fn header(s:wire_runtime::State&,status:u32,payload:u32,required:u32,items:u32,detail:u32) {
 assert(get(s.egress,0)==0x4b310001 && get(s.egress,4)==27 && get(s.egress,8)==status && get(s.egress,12)==payload);
 assert(get(s.egress,16)==required && get(s.egress,20)==items && get(s.egress,24)==detail && get(s.egress,28)==0);
}
fn clean(s:wire_runtime::State&) {assert(!s.busy && s.frames==9 && s.slots[0].state==0 && s.bitmap[0]==0);}
fn input(s:wire_runtime::State&) {
 for i in 256 {s.ingress[i]=0;s.egress[i]=0xa5;}
 put(s.ingress,0,0x4b310001);put(s.ingress,4,27);put(s.ingress,12,72);
 put(s.ingress,32,10);put(s.ingress,36,3);put(s.ingress,40,36);
 put(s.ingress,44,3);put(s.ingress,48,48);put(s.ingress,52,3);put(s.ingress,56,60);
 put(s.ingress,60,3);put(s.ingress,64,72);
 put(s.ingress,68,0xffffffff);put(s.ingress,72,0x12345678);put(s.ingress,76,0);
 put(s.ingress,80,1);put(s.ingress,84,0);put(s.ingress,88,1);
 put(s.ingress,92,0x3f800000);put(s.ingress,96,0x7fc00001);put(s.ingress,100,0x80000000);
}
fn contract(selected:u32,alias:bool) -> wire_contract::Contract {
 var c=wire_contract::Contract {field_count:5,selected:selected,alias_result:alias};
 c.fields[0]=host_bridge::Field {kind:1};
 c.fields[1]=host_bridge::Field {role:1,kind:1,max_count:4,domain_binder:1};
 c.fields[2]=host_bridge::Field {role:1,kind:3,max_count:4,domain_binder:2};
 c.fields[3]=host_bridge::Field {role:1,kind:2,max_count:4,domain_binder:3};
 c.fields[4]=host_bridge::Field {role:1,kind:0,max_count:4,domain_binder:4};
 c.manifest=host_bridge::Manifest {export_id:27,ingress_bytes:256,egress_bytes:256,output_kind:c.fields[selected].kind,
     output_capacity:if alias {1} else {4},result_max_count:4,required_domain_mask:15,work_bytes:64,output_items_are_count:true};
 return c;
}
fn main() {
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 var state=wire_runtime::State {};state.frames=9;
 for selected in 1..5 {
  for mode in 2 {
   var c=contract(selected as u32,mode==1);
   assert(wire_contract::shape(c) && wire_validate::shape(c));
   var made=wire_contract::make(source,c);assert(made.status==0 && wire_validate::verify(made.spec,source,c));
   input(state);let original=copy(state.ingress);let calls=state.calls;
   let stride=host_bridge::stride(c.manifest.output_kind);let required=8+3*stride;
   assert(wire_runtime::invoke(state,made.spec,source,c,27,104,required,0)==0);
   clean(state);header(state,0,required,required,3,0);
   assert(state.calls==calls+1 && state.ingress[..]==original[..]);
   assert(get(state.egress,32)==3 && get(state.egress,36)==8);
   let offset=if selected==1 {68} else if selected==2 {80} else {92};
   for i in 3*stride {assert(state.egress[40+i]==original[offset+i]);}
   for i in (40+3*stride as i64)..256 {assert(state.egress[i]==0xa5);}
   // Capacity is checked after exactly one execution and publishes no payload.
   input(state);let before=copy(state.egress);let runs=state.calls;
   assert(wire_runtime::invoke(state,made.spec,source,c,27,104,required-1,0)==2);
   clean(state);header(state,2,0,required,3,0);assert(state.calls==runs+1 && state.egress[32..]==before[32..]);
  }
 }
 var c=contract(1,false);var made=wire_contract::make(source,c);assert(made.status==0);
 for fault in 1..4 {
  input(state);let old=copy(state.egress);let calls=state.calls;
  let code=if fault==1 {3} else if fault==2 {5} else {6};
  let detail=if fault==2 {0} else {1};
  assert(wire_runtime::invoke(state,made.spec,source,c,27,104,20,fault as u32)==code);
  clean(state);header(state,code as u32,0,0,0,detail as u32);assert(state.egress[32..]==old[32..]);
  assert(state.calls==calls+(if fault==3 {1} else {0}));
 }
 input(state);state.busy=true;let before_in=copy(state.ingress);let before_out=copy(state.egress);let calls=state.calls;
 assert(wire_runtime::invoke(state,made.spec,"invalid source",c,0,0,0,0)==4);
 assert(state.busy && state.frames==9 && state.calls==calls && state.ingress[..]==before_in[..] && state.egress[..]==before_out[..]);state.busy=false;
 for change in 4 {
  input(state);if change==0 {put(state.ingress,80,2);} else if change==1 {put(state.ingress,40,37);}
  else if change==2 {put(state.ingress,36,5);} else {put(state.ingress,64,73);}
  let old=copy(state.egress);let runs=state.calls;
  assert(wire_runtime::invoke(state,made.spec,source,c,27,104,20,0)==1);
  clean(state);header(state,1,0,0,0,0);assert(state.calls==runs && state.egress[32..]==old[32..]);
 }
 // Immutable input ranges may overlap; each is still copied into its own
 // builder and frozen with a distinct fixture domain before invocation.
 input(state);put(state.ingress,48,36);put(state.ingress,68,1);put(state.ingress,72,0);put(state.ingress,76,1);
 put(state.ingress,80,0);put(state.ingress,84,0);put(state.ingress,88,0);
 assert(wire_runtime::invoke(state,made.spec,source,c,27,104,20,0)==0);
 clean(state);assert(get(state.egress,40)==1 && get(state.egress,44)==0 && get(state.egress,48)==1);
 let host_owned=copy(state.egress);
 input(state);assert(wire_runtime::invoke(state,made.spec,source,c,27,104,20,0)==0);
 assert(get(host_owned,40)==1 && get(host_owned,44)==0 && get(host_owned,48)==1);
 // Repeated Nat witnesses and preconditions are checked before reservation.
 var guarded=contract(1,false);guarded.fields[1].max_count=3;guarded.fields[2].max_count=3;
 guarded.fields[1].nat_binder=1;guarded.fields[2].nat_binder=1;
 guarded.manifest.output_nat_binder=1;guarded.manifest.required_nat_mask=1;guarded.manifest.output_capacity=3;
 guarded.predicate_count=1;guarded.predicates[0]=host_bridge::Predicate {kind:0,
     left:host_bridge::Term {kind:1,field:0},right:host_bridge::Term {literal:10}};
 var guarded_spec=wire_contract::make(source,guarded);assert(guarded_spec.status==0 && wire_validate::verify(guarded_spec.spec,source,guarded));
 input(state);assert(wire_runtime::invoke(state,guarded_spec.spec,source,guarded,27,104,20,0)==0);clean(state);
 input(state);put(state.ingress,32,11);let skipped=state.calls;
 assert(wire_runtime::invoke(state,guarded_spec.spec,source,guarded,27,104,20,0)==1);clean(state);assert(state.calls==skipped);
 input(state);put(state.ingress,44,2);
 assert(wire_runtime::invoke(state,guarded_spec.spec,source,guarded,27,104,20,0)==1);clean(state);assert(state.calls==skipped);
 // Mutating either the independently supplied manifest, source or encoded
 // dictionary declines this private fixture before any state/window write.
 input(state);let all=copy(state.egress);let before=state.calls;
 var altered=c;altered.fields[1].max_count=3;
 assert(wire_runtime::invoke(state,made.spec,source,altered,27,104,20,0)==9);
 assert(wire_runtime::invoke(state,made.spec,"wrong",c,27,104,20,0)==9);
 made.spec.dictionary.dictionary.size=8;
 assert(wire_runtime::invoke(state,made.spec,source,c,27,104,20,0)==9);
 clean(state);assert(state.egress[..]==all[..] && state.calls==before);
 print("source/manifest-bound scalar copy-bridge fixture passed");
}
