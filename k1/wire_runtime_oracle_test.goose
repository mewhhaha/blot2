import wire_contract;
import wire_runtime;
import host_bridge;
fn random(s:u32&)->u32 {s^=s<<13;s^=s>>17;s^=s<<5;return s;}
fn put(s:u8[:],p:i64,v:u32) {for i in 4 {s[p+i]=(v >> (8*i) & 255) as u8;}}
fn word(s:u8[:],p:i64)->u32 {return s[p] | (s[p+1] as u32 <<8) | (s[p+2] as u32 <<16) | (s[p+3] as u32 <<24);}
// Independent specialized decoder for this single fixed schema.
fn valid(s:u8[:],id:u32,input_bytes:u32,cap:u32)->bool {
 if id!=27 || input_bytes<32 || input_bytes>256 || cap>224 {return false;}
 let payload=input_bytes-32;
 if word(s,0)!=0x4b310001 || word(s,4)!=27 || word(s,8)!=0 || word(s,12)!=payload ||
    word(s,16)!=0 || word(s,20)!=0 || word(s,24)!=0 || word(s,28)!=0 || payload<12 {return false;}
 let count=word(s,36);let offset=word(s,40);
 if count>4 || offset%4!=0 || offset<12 || offset>payload || count*4>payload-offset {return false;}
 for i in 12..payload {if !(i>=offset && i<offset+count*4) && s[32+i]!=0 {return false;}}
 return true;
}
fn main() {
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 var c=wire_contract::Contract {field_count:2,selected:1};
 c.fields[0]=host_bridge::Field {kind:1};c.fields[1]=host_bridge::Field {role:1,kind:1,max_count:4,domain_binder:1};
 c.manifest=host_bridge::Manifest {export_id:27,ingress_bytes:256,egress_bytes:256,output_kind:1,output_capacity:4,result_max_count:4,required_domain_mask:1,work_bytes:32,output_items_are_count:true};
 var made=wire_contract::make(source,c);assert(made.status==0);
 var seed:u32=0x7a139ccd;var accepted=0;var rejected=0;var small=0;var success=0;
 for trial in 12000 {
  var st=wire_runtime::State {};st.frames=9;for p in 256 {st.egress[p]=0xa5;}
  let n=random(seed)%5;let offset=12+(random(seed)%5)*4;let payload=offset+n*4+(random(seed)%3)*4;
  put(st.ingress,0,0x4b310001);put(st.ingress,4,27);put(st.ingress,12,payload);
  put(st.ingress,32,random(seed));put(st.ingress,36,n);put(st.ingress,40,offset);
  for i in n {put(st.ingress,32+offset as i64+i as i64*4,random(seed));}
  var inbytes=32+payload;var capacity=random(seed)%40;var id:u32=27;
  let mutation=random(seed)%7;
  if mutation==1 {let pos=random(seed)%256;st.ingress[pos]^=(random(seed)%255+1) as u8;}
  else if mutation==2 {put(st.ingress,36,random(seed));}
  else if mutation==3 {put(st.ingress,40,random(seed));}
  else if mutation==4 {inbytes=random(seed)%300;}
  else if mutation==5 {capacity=random(seed)%250;}
  else if mutation==6 {id=random(seed);}
  let original=copy(st.ingress);let prior=copy(st.egress);let okay=valid(st.ingress,id,inbytes,capacity);
  let got=wire_runtime::invoke(st,made.spec,source,c,id,inbytes,capacity,0);
  assert(st.ingress[..]==original[..] && !st.busy && st.frames==9 && st.slots[0].state==0 && st.bitmap[0]==0);
  assert(word(st.egress,0)==0x4b310001 && word(st.egress,4)==27 && word(st.egress,28)==0);
  if !okay {
   rejected+=1;assert(got==1 && st.calls==0 && word(st.egress,8)==1 && word(st.egress,12)==0 && word(st.egress,16)==0 && word(st.egress,20)==0 && word(st.egress,24)==0);
   assert(st.egress[32..]==prior[32..]);
  } else {
   accepted+=1;let count=word(st.ingress,36);let start=word(st.ingress,40);let need=8+count*4;assert(st.calls==1);
   if capacity<need {
    small+=1;assert(got==2 && word(st.egress,8)==2 && word(st.egress,12)==0 && word(st.egress,16)==need && word(st.egress,20)==count);
    assert(st.egress[32..]==prior[32..]);
   } else {
    success+=1;assert(got==0 && word(st.egress,8)==0 && word(st.egress,12)==need && word(st.egress,16)==need && word(st.egress,20)==count);
    assert(word(st.egress,32)==count && word(st.egress,36)==8);
    for i in count {assert(word(st.egress,40+i as i64*4)==word(st.ingress,32+start as i64+i as i64*4));}
    for p in 32+need..256 {assert(st.egress[p]==0xa5);}
   }
  }
 }
 assert(accepted>0 && rejected>0 && small>0 && success>0);
 print("independent wire U32 differential: accepted ",accepted,", rejected ",rejected,", too small ",small,", success ",success);
}
