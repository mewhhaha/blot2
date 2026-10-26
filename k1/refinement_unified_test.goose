import std;
import os;
import unified_frontend;
import unified_wasm;
import unified_check;
import unified_guard;
import work;
fn main() {
    let accepted = [
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 && x + 1 < 5:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 && #True:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let a = 0\n  else:\n    return x\n  return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 || #False:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 || x < 4294967295:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if #False && x < 4294967295:\n    return x + 1\n  return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y < 4294967295 && #True:\n    return x + 1\n  return x\n"
    ];
    for source,i in accepted {
        var parsed=unified_frontend::parse(source);
        if parsed.status!=0 {print(str("unexpected rejection ",i," status ",parsed.status));}
        assert(parsed.status==0 && unified_check::verify(source,parsed.program));
        let bytes=unified_wasm::emit(source,parsed.program);assert(bytes.len>0 && write_file(str("refinement-",i,".wasm"),bytes));
    }
    let rejected = [
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 || x + 1 < 10:\n    return x\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if #True || x < 4294967295:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 && #True:\n    return x\n  else:\n    return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let a = 0\n  else:\n    let b = 0\n  return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = U32.wrapping_add(x,1)\n    return y + 1\n  return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 2\n  return x\n"
    ];
    for source,i in rejected {
        let p=unified_frontend::parse(source);if p.status!=5 {print(str("unexpected negative status ",i," -> ",p.status));}assert(p.status==5);
    }
    var good=unified_frontend::parse(accepted[1]);var m=work::Meter {};
    let yes=unified_guard::check_with_work(accepted[1],good.program,m);assert(yes.status==0 && yes.evidence.len>0 && m.proof_visits>0);
    let used=m.semantic;var limited=work::Meter {semantic:1048576-used+1};
    let no=unified_guard::check_with_work(accepted[1],good.program,limited);assert(no.status==2 && no.receipt.quantity==1 && no.evidence.len==0);
    print("unified short-circuit and join successor checks passed");
}
