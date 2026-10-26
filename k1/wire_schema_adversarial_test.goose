// Producer/independent schema differential; no public ABI authority is inferred.
import wire_contract;
import wire_validate;
import host_bridge;
fn next(state:u64&) -> u32 {state=(state*1664525+1013904223)&4294967295;return state as u32;}
fn main() {
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 var state:u64=123456789;var accepted:i64=0;var rejected:i64=0;
 for _ in 6000 {
  var c=wire_contract::Contract {field_count:2,selected:1};
  c.fields[0]=host_bridge::Field {kind:1};
  c.fields[1]=host_bridge::Field {role:1,kind:1,max_count:4,domain_binder:1};
  c.manifest=host_bridge::Manifest {export_id:27,ingress_bytes:256,egress_bytes:256,output_kind:1,
      output_capacity:4,result_max_count:4,required_domain_mask:1,work_bytes:32};
  let pick=next(state)%23;let value=next(state);
  if pick==0 {c.field_count=value%11;} else if pick==1 {c.selected=value%11;}
  else if pick==2 {c.predicate_count=value%11;} else if pick==3 {c.fields[1].role=value%4;}
  else if pick==4 {c.fields[1].kind=value%6;} else if pick==5 {c.fields[1].max_count=value%20;}
  else if pick==6 {c.fields[1].nat_binder=value%35;} else if pick==7 {c.fields[1].domain_binder=value%35;}
  else if pick==8 {c.fields[0].kind=value%6;} else if pick==9 {c.fields[0].max_count=value%2;}
  else if pick==10 {c.fields[0].nat_binder=value%2;} else if pick==11 {c.fields[0].domain_binder=value%2;}
  else if pick==12 {c.manifest.output_kind=value%6;} else if pick==13 {c.manifest.output_capacity=value%20;}
  else if pick==14 {c.manifest.result_max_count=value%20;} else if pick==15 {c.manifest.required_nat_mask=value%4;}
  else if pick==16 {c.manifest.required_domain_mask=value%4;} else if pick==17 {c.manifest.work_bytes=value%70;}
  else if pick==18 {c.manifest.output_nat_binder=value%35;} else if pick==19 {c.manifest.ingress_bytes=value%300;}
  else if pick==20 {c.manifest.egress_bytes=value%300;} else if pick==21 {c.alias_result=value%2==0;}
  else {
   c.predicate_count=1;c.predicates[0]=host_bridge::Predicate {kind:value%8,
     left:host_bridge::Term {kind:next(state)%5,field:next(state)%4,literal:next(state)%2},
     right:host_bridge::Term {kind:next(state)%5,field:next(state)%4,literal:next(state)%2}};
  }
  let a=wire_contract::shape(c);let b=wire_validate::shape(c);assert(a==b);
  if a {accepted+=1;var made=wire_contract::make(source,c);assert(made.status==0 && wire_validate::verify(made.spec,source,c));}
  else {rejected+=1;assert(wire_contract::make(source,c).status!=0);}
 }
 assert(accepted>0 && rejected>0);
 print("independent wire schema differential passed");
}
