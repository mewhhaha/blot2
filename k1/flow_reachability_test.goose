import flow_parse;
import flow_verify;
import flow_completion;
fn case(s: u8[:], expected: i64) { var t, status = flow_parse::parse(s); assert(status==0 && flow_verify::verify(t)); assert(flow_completion::check(t)==expected); }
fn main() {
 case("do:\n  if #True:\n    return 1\n  else:\n    return do:\n      if x:\n        break 2\n",0);
 case("do:\n  if #False:\n    return 1\n  else:\n    return do:\n      if x:\n        break 2\n",9);
 case("do:\n  return do:\n    if #True:\n      break 1\n    else:\n      if y:\n        break 2\n",0);
 case("do:\n  return do:\n    if #False:\n      break 1\n",9);
 case("do:\n  return #False && do:\n    if x:\n      break #True\n",0);
 case("do:\n  return #True && do:\n    if x:\n      break #True\n",9);
 case("do:\n  return #True || do:\n    if x:\n      break #True\n",0);
 case("do:\n  return #False || do:\n    if x:\n      break #True\n",9);
 case("do:\n  if #True:\n    return 1\n  else:\n    return 2\n    return 3\n",8);
 print("independent literal-pruned reachability controls passed");
}
