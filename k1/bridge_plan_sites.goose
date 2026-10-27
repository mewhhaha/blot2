// Closed bounded instruction-template reader. It yields compiler-local sites
// only; final independently checked target must still match exact source.
namespace bridge_plan_sites;
import i08_same_target;
import m12_caller_flow_bytes;
struct Result {ok:bool=false,sites:i64[12]=[0;12]}
fn scan(code:u8[:])->Result {
 if code.len<3 || code[..3]!=[1 as u8,13,0x7f] {return Result {};}
 let calls:i64[12]=[16,18,0,19,5,6,8,21,13,12,11,19];
 var pos:i64=3;var depth:i64=0;var count:i64=0;var finished:bool=false;var sites:i64[12]=[0;12];var scopes:u8[128]=[0;128];var has_else:bool[128]=[false;128];
 while pos<code.len {
  let site=pos;let op=code[pos];pos+=1;
  if op==2 || op==3 || op==4 {
   if pos>=code.len || depth>=128 || (code[pos]!=0x40 && code[pos]!=0x7f){return Result {};}
   pos+=1;scopes[depth]=op;has_else[depth]=false;depth+=1;
  }else if op==5 {if depth<1 || scopes[depth-1]!=4 || has_else[depth-1]{return Result {};}has_else[depth-1]=true;}
  else if op==11 {if depth>0 {depth-=1;}else if pos!=code.len{return Result {};}else {finished=true;}}
  else if op==0x10 {
   let n=i08_same_target::read_leb(code,pos,code.len);if !n.ok || n.next!=pos+1 || count>=12 || n.value!=calls[count] ||
    (count==3 && depth!=1) || (count!=3 && depth!=0){return Result {};}
   sites[count]=site;count+=1;pos=n.next;
  }else if op==0x0c || op==0x0d || op==0x20 || op==0x21 || op==0x22 {
   let n=i08_same_target::read_leb(code,pos,code.len);if !n.ok{return Result {};}
   if (op==0x0c || op==0x0d) && n.value>depth {return Result {};}
   if (op==0x20 || op==0x21 || op==0x22) && n.value>=16 {return Result {};}
   pos=n.next;
  }
  else if op==0x41 {pos=m12_caller_flow_bytes::skip_signed(code,pos);}
  else if op==0x28 || op==0x2d || op==0x36 || op==0x3a {
   pos=m12_caller_flow_bytes::unsigned_end(code,pos);if pos<0{return Result {};}pos=m12_caller_flow_bytes::unsigned_end(code,pos);
  }else if op!=0 && op!=0x0f && op!=0x45 && op!=0x46 && op!=0x47 && op!=0x48 && op!=0x49 && op!=0x4b && op!=0x4c && op!=0x4d && op!=0x4f && op!=0x6a && op!=0x6b && op!=0x6c && op!=0x71 && op!=0x72 {return Result {};}
  if pos<0 || pos>code.len{return Result {};}
 }
 if depth!=0 || count!=12 || !finished{return Result {};}
 return Result {ok:true,sites:sites};
}
