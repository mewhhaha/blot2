import wire_contract;
import wire_validate;
import wire_runtime;
import host_bridge;
fn put(b:u8[:],p:i64,v:u32) {for i in 4 {b[p+i]=(v >> (8*i) & 255) as u8;}}
fn get(b:u8[:],p:i64)->u32 {return b[p] | (b[p+1] as u32 << 8) | (b[p+2] as u32 << 16) | (b[p+3] as u32 << 24);}
fn main() {
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 var c=wire_contract::Contract {field_count:3,selected:0};
 c.fields[0]=host_bridge::Field {role:1,kind:1,max_count:3,domain_binder:1};
 c.fields[1]=host_bridge::Field {role:1,kind:3,max_count:3,domain_binder:2};
 c.fields[2]=host_bridge::Field {role:1,kind:0,max_count:3,domain_binder:3};
 c.manifest=host_bridge::Manifest {export_id:42,ingress_bytes:256,egress_bytes:256,output_kind:1,output_capacity:3,result_max_count:3,required_domain_mask:7,work_bytes:36,output_items_are_count:true};
 var state=wire_runtime::State {};var cases=0;
 for mode in 2 {c.alias_result=mode==1;var made=wire_contract::make(source,c);assert(made.status==0 && wire_validate::verify(made.spec,source,c));
  for n0 in 4 {for n1 in 4 {for a in 5 {for b in 5 {
   for i in 256 {state.ingress[i]=0;state.egress[i]=0xa5;}
   let o0=(24+a*4) as u32;let o1=(24+b*4) as u32;
   put(state.ingress,0,0x4b310001);put(state.ingress,4,42);put(state.ingress,12,64);
   put(state.ingress,32,n0 as u32);put(state.ingress,36,o0);put(state.ingress,40,n1 as u32);put(state.ingress,44,o1);put(state.ingress,48,3);put(state.ingress,52,25);
   for word in 6..16 {let off=word*4;let covered=(off>=o0 && off<o0+n0*4) || (off>=o1 && off<o1+n1*4);if covered {put(state.ingress,32+off as i64,(word%2) as u32);}}
   let before=copy(state.ingress);let calls=state.calls;
   assert(wire_runtime::invoke(state,made.spec,source,c,42,96,(8+n0*4) as u32,0)==0);
   assert(!state.busy && state.frames==0 && state.bitmap[0]==0 && state.slots[0].state==0 && state.calls==calls+1 && state.ingress[..]==before[..]);
   assert(get(state.egress,8)==0 && get(state.egress,12)==8+n0*4 && get(state.egress,20)==n0 && get(state.egress,32)==n0 && get(state.egress,36)==8);
   for i in n0*4 {assert(state.egress[40+i]==before[32+o0+i]);}cases+=1;
  }}}}
 }
 assert(cases==800);
 c.alias_result=false;var made=wire_contract::make(source,c);assert(made.status==0);
 for mode in 6 {
  for i in 256 {state.ingress[i]=0;state.egress[i]=0xa5;}
  put(state.ingress,0,0x4b310001);put(state.ingress,4,42);put(state.ingress,12,64);
  put(state.ingress,32,1);put(state.ingress,36,24);put(state.ingress,40,1);put(state.ingress,44,28);put(state.ingress,48,0);put(state.ingress,52,25);
  if mode==0 {put(state.ingress,40,4);}else if mode==1 {put(state.ingress,36,25);}else if mode==2 {put(state.ingress,36,20);}
  else if mode==3 {put(state.ingress,60,2);}else if mode==4 {state.ingress[61]=1;}else {put(state.ingress,52,65);}
  let before=copy(state.memory);let payload=copy(state.egress);let calls=state.calls;let old=state.slots[0].generation;
  assert(wire_runtime::invoke(state,made.spec,source,c,42,96,20,0)==1);
  assert(!state.busy && state.bitmap[0]==0 && state.slots[0].generation==old && state.calls==calls && state.memory[..]==before[..] && state.egress[32..]==payload[32..]);
 }
 print("800 overlap, Bool, Unit, and failure atomicity controls passed");
}
