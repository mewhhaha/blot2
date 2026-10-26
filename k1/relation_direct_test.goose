import std;
import os;
import unified_frontend;
import unified_guard;
import refinement_guard_verify;
import unified_check;
import unified_wasm;
fn main() {
    let accepted=[
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  let z = x\n  if z < y:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y && x + 1 < y:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x < U32.wrapping_add(x,1):\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y:\n    let q = 0\n  else:\n    return x\n  return x + 1\n"
    ];
    for source,i in accepted {
        var parsed=unified_frontend::parse(source);if parsed.status!=0 {print(str("unexpected rejection ",i," status ",parsed.status));}
        assert(parsed.status==0 && unified_check::verify(source,parsed.program));
        let proof=unified_guard::check(source,parsed.program);assert(proof.status==0 && proof.evidence.len>0 && proof.evidence[0].guard_true);
        assert(refinement_guard_verify::verify_evidence(source,parsed.program,proof.evidence));
        for field in 6 {
            var forged:unified_guard::Evidence[>..]=[];forged.append(proof.evidence);
            if field==0 {forged[0].guard_id+=1;} else if field==1 {forged[0].guard_true=false;}
            else if field==2 {forged[0].subject+=1;} else if field==3 {forged[0].reference+=1;}
            else if field==4 {forged[0].one+=1;} else {forged[0].addition+=1;}
            assert(!refinement_guard_verify::verify_evidence(source,parsed.program,forged));
        }
        let bytes=unified_wasm::emit(source,parsed.program);assert(bytes.len>0 && write_file(str("relation-direct-",i,".wasm"),bytes));
    }
    for source in [
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < x:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 4294967295:\n    return x + 1\n  return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y || x + 1 < y:\n    return x\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y:\n    return y + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x <= y:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < y:\n    return x\n  else:\n    return x + 1\n"
    ] {let rejected=unified_frontend::parse(source);assert(rejected.status==5 && rejected.program.nodes.len==0);}
    print("source-bound strict U32 relation successor proofs passed");
}
