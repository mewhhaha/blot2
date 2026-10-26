import std;
import os;
import ownership_parse;
import ownership_check;
import ownership_runtime;
import owned_scalar_source;
import owned_scalar_runtime;
fn main() {
 let argv=args(); if argv.len!=3 {exit(2);}
 var src:u8[>..]=[];if !read_file(argv[1],src) {exit(3);}
 let mode:i64=if argv[2]=="0" {0} else if argv[2]=="1" {1} else {2};
 var parsed=ownership_parse::parse(src);if parsed.status!=0 {print("parse ",parsed.status);return;}
 var contract=ownership_check::Contract {owner:"original",flag:"condition",return_mode:mode};
 let status=ownership_check::check(parsed.tree,src,contract);if status!=0 {print("check ",status);return;}
 let owned="owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,42)\n";
 let core=owned_scalar_source::parse(owned);if core.status!=0 {exit(4);}
 for flag in 2 {
  var clock=owned_scalar_runtime::Clock {};var state=owned_scalar_runtime::State {};
  if !owned_scalar_runtime::initialize(state,clock) {exit(5);}
  let constructed=owned_scalar_runtime::construct(state,owned,core.core);if constructed.status!=0 {exit(6);}
  let result=ownership_runtime::run(parsed.tree,src,contract,state,constructed.handle,flag==1);
  if result.status!=0 {exit(7);}
  if mode==1 {
   if !result.returned_owner || !owned_scalar_runtime::live(state,result.handle) {exit(8);}
   if owned_scalar_runtime::close(state,result.handle).status!=0 {exit(9);}
  } else if mode==2 && result.value!=42 {exit(10);}
  if state.slot!=0 || state.bitmap[0]!=0 || state.loan_count!=0 {exit(11);}
 }
 print("accept");
}
