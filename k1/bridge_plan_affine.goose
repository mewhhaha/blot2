// Compiler-local affine states; never runtime capability handles.
namespace bridge_plan_affine;
struct State {frame:bool=false,owner:bool=false,space:u32=0,input:u32=0,output:u32=0,handled:bool=false,done:bool=false}
// Resource roles, not caller-supplied numeric region/domain identities.
// Input: 0 absent, 1 uninitialized Dest, 2 fully initialized, 3 read View.
// Output: 0 absent, 1 exclusive Dest, 2 returned frozen View.
// Space versions 1/2/3 are local states, not identities or runtime handles.
fn transition(st:State&,kind:u32)->bool {
 if st.done{return false;}
 if kind==1 {if st.frame || st.owner{return false;}st.frame=true;}
 else if kind==2 {if !st.frame || st.owner || st.space!=0{return false;}st.owner=true;st.space=1;}
 else if kind==3 {if !st.owner || st.space!=1 || st.input!=0{return false;}st.space=2;st.input=1;}
 else if kind==4 {if !st.owner || st.input!=1{return false;}st.input=2;}
 else if kind==5 {if !st.owner || st.input!=2{return false;}st.input=3;}
 else if kind==6 {if !st.owner || st.space!=2 || st.output!=0 || st.input!=3{return false;}st.space=3;st.output=1;}
 // The independently checked source adapter consumes the output Dest, begins
 // its Builder, invokes the checked kernel with input read loan, and returns
 // its exact freeze-origin result View. Range cases establish nonoverlap.
 else if kind==7 {if !st.owner || st.input!=3 || st.output!=1 || st.space!=3{return false;}st.output=2;}
 // Result handling either finishes copy-out or takes OutputTooSmall with no
 // payload publication; both complete before ending the result loan.
 else if kind==8 {if st.input!=3 || st.output!=2 || st.handled{return false;}st.handled=true;}
 else if kind==9 {if st.output!=2 || !st.handled{return false;}st.output=0;}
 else if kind==10 {if st.input!=3 || st.output!=0{return false;}st.input=0;}
 // This explicit compiler-Core operation consumes the remaining Space. It is
 // erased, so its site is immediately before the checked close call.
 else if kind==11 {if !st.owner || st.space!=3 || st.input!=0 || st.output!=0{return false;}st.space=0;}
 else if kind==12 {if !st.owner || st.space!=0 || st.input!=0 || st.output!=0{return false;}st.owner=false;}
 else if kind==13 {if !st.frame || st.owner || st.space!=0 || st.input!=0 || st.output!=0 || !st.handled{return false;}st.frame=false;st.done=true;}
 else{return false;}return true;
}
// Failed reserve creates no owner or Space. The verified actual error branch
// leaves the already-entered frame before publishing the reservation error.
fn reserve_failure(st:State&)->bool {
 if !st.frame || st.owner || st.space!=0 || st.input!=0 || st.output!=0 || st.handled || st.done{return false;}
 st.frame=false;st.done=true;return true;
}

// Replays invocation-local resources on each status edge. Busy, invalid and
// frame-limit paths create no resources; reserve failure leaves only a frame.
// Success and OutputTooSmall share all loan/Space/owner/frame cleanup. The
// trap edge explicitly poisons the instance and makes no cleanup claim.
fn branch_exit(kind:u32,cleanup:u32,phase:u32)->bool {
 if kind>=1 && kind<=3 {return cleanup==0 && phase==0;}
 if kind==4 {if cleanup!=1 || phase!=1{return false;}var st=State {frame:true};return reserve_failure(st) && st.done && !st.frame && !st.owner && st.space==0;}
 if kind==5 || kind==6 {
  if cleanup!=2 || phase!=7{return false;}var st=State {};
  for i in 7 {if !transition(st,(i+1) as u32){return false;}}
  if !st.frame || !st.owner || st.space!=3 || st.input!=3 || st.output!=2 || st.handled{return false;}
  for i in 6 {if !transition(st,(i+8) as u32){return false;}}
  return st.done && !st.frame && !st.owner && st.space==0 && st.input==0 && st.output==0;
 }
 if kind==7 {return cleanup==3 && phase==255;}return false;
}
