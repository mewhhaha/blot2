import ownership_parse;
import ownership_verify;
import ownership_check;
fn test(s:u8[:],mode:i64,want:i64) {
    var p=ownership_parse::parse(s); if p.status!=0 {print("parse status ",p.status," source ",s);} else if !ownership_verify::verify(p.tree) {print("verification failed ",s);} assert(p.status==0 && ownership_verify::verify(p.tree));
    var c=ownership_check::Contract {owner:"original",flag:"condition",return_mode:mode};
    let result=ownership_check::check(p.tree,s,c);
    if result!=want {print("got ",result," want ",want," source ",s);}
    assert(result==want);
}
fn main() {
    test("do:\n  owned.close(original)\n  return ()\n",0,0);
    test("do:\n  let first = original\n  let second = first\n  return second\n",1,0);
    test("do:\n  let x = owned.open(original) as region_a item_a in do:\n    break item_a\n  let y = owned.open(original) as region_b item_b in do:\n    break item_b\n  owned.close(original)\n  return y\n",2,0);
    test("do:\n  let x = owned.open(original) as outer item_a in do:\n    let y = owned.open(original) as inner item_b in do:\n      break item_b\n    break item_a\n  owned.close(original)\n  return x\n",2,0);
    test("do:\n  if condition:\n    let moved = original\n    return moved\n  else:\n    return original\n",1,0);
    test("do:\n  if condition:\n    let moved = original\n    owned.close(moved)\n  else:\n    owned.close(original)\n  return ()\n",0,0);
    test("do:\n  if condition:\n    owned.close(original)\n    return ()\n  owned.close(original)\n  return ()\n",0,0);
    test("do:\n  let x = owned.open(original) as outer item_a in do:\n    if condition:\n      break item_a\n    else:\n      break item_a\n  owned.close(original)\n  return x\n",2,0);
    test("do:\n  return ()\n",0,2);
    test("do:\n  let moved = original\n  return original\n",1,2);
    test("do:\n  let moved = original\n  let moved = moved\n  return moved\n",1,2);
    test("do:\n  let x = owned.open(original) as original item in do:\n    break item\n  owned.close(original)\n  return x\n",2,2);
    test("do:\n  let x = owned.open(original) as zone zone in do:\n    break zone\n  owned.close(original)\n  return x\n",2,2);
    test("do:\n  let x = owned.open(original) as zone item in do:\n    owned.close(original)\n    break item\n  return x\n",2,3);
    test("do:\n  let x = owned.open(original) as zone item in do:\n    return original\n  owned.close(original)\n  return x\n",1,3);
    test("do:\n  if condition:\n    owned.close(original)\n  return ()\n",0,4);
    test("do:\n  if condition:\n    let moved = original\n  else:\n    let moved = original\n  return moved\n",1,4);
    test("do:\n  if condition:\n    owned.close(original)\n    return ()\n",0,5);
    test("do:\n  let x = owned.open(original) as zone item in do:\n    if condition:\n      break item\n  owned.close(original)\n  return x\n",2,5);
    test("do:\n  owned.close(original)\n  return ()\n  owned.close(original)\n",0,6);
    test("do:\n  break original\n",0,7);
    test("do:\n  let x = owned.open(original) as outer item_a in do:\n    let y = owned.open(original) as inner item_b in do:\n      break item_a\n    break item_a\n  owned.close(original)\n  return x\n",2,7);
    print("general-named owned scopes, loans and branches passed");
}
