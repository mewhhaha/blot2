import ownership_parse;
import ownership_check;
fn reject(s:u8[:],mode:i64,want:i64) {var t=ownership_parse::parse(s);assert(t.status==0);var c=ownership_check::Contract {owner:"original",flag:"condition",return_mode:mode};let got=ownership_check::check(t.tree,s,c);if got!=want {print("got ",got," expected ",want," ",s);}assert(got==want);}
fn main() {
 reject("do:\n  let moved = original\n  owned.close(original)\n  return ()\n",0,2);
 reject("do:\n  let condition = original\n  return condition\n",1,2);
 reject("do:\n  if original:\n    return original\n  else:\n    return original\n",1,2);
 reject("do:\n  let v = owned.open(original) as r p in do:\n    let moved = original\n    break p\n  owned.close(original)\n  return v\n",2,3);
 reject("do:\n  let v = owned.open(original) as outer p in do:\n    let w = owned.open(original) as inner q in do:\n      break p\n    break p\n  owned.close(original)\n  return v\n",2,7);
 reject("do:\n  let v = owned.open(original) as outer p in do:\n    let w = owned.open(original) as inner q in do:\n      break q\n    break p\n  owned.close(original)\n  return w\n",2,2);
 reject("do:\n  if condition:\n    let moved = original\n  else:\n    let moved = original\n  return moved\n",1,4);
 reject("do:\n  let v = owned.open(original) as zone item in do:\n    owned.close(original)\n    break item\n  return v\n",2,3);
 reject("do:\n  let v = owned.open(original) as zone item in do:\n    break item\n  let moved = v\n  owned.close(original)\n  return moved\n",2,2);
 print("independent name, branch, move, loan and escape negatives passed");
}
