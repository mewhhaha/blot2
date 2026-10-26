import std;
import os;
import unified_frontend;
import unified_wasm;
import unified_check;
import unified_guard;
import refinement_guard_verify;
fn main() {
    let cases=[
      "let f: U32 -> U32 = fn x => do:\n  if x <= 4294967294:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if 4294967294 < x:\n    return x\n  else:\n    return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if 4294967295 <= x:\n    return x\n  else:\n    return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x <= 4294967294 && x + 1 <= 5:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y <= 4294967294:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if 4294967294 < x:\n    return x\n  return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x <= 10:\n    return 1\n  else:\n    return 0\n",
      "let f: U32 -> U32 = fn x => do:\n  if ((#True && (((x < 4294967295 && x < 0) || (#False || x < 4294967295)) && ((#False && x < 1) || x < 1))) && ((#True || ((#False || #False) && (x + 1 < 5 || x + 1 < 5))) && x < 4294967295)):\n    return x + 1\n  else:\n    return x\n"
    ];
    for source,i in cases {
        var p=unified_frontend::parse(source);if p.status!=0 {print(str("unexpected rejection ",i," status ",p.status));}
        assert(p.status==0 && unified_check::verify(source,p.program));
        let evidence=unified_guard::check(source,p.program);
        assert(evidence.status==0 && refinement_guard_verify::verify_evidence(source,p.program,evidence.evidence));
        if i==1 || i==2 || i==5 { assert(evidence.evidence.len>0 && !evidence.evidence[0].guard_true); }
        if evidence.evidence.len>0 {
            for field in 6 {
                var forged:unified_guard::Evidence[>..]=[];forged.append(evidence.evidence);
                if field==0 {forged[0].guard_id+=1;} else if field==1 {forged[0].guard_true=!forged[0].guard_true;}
                else if field==2 {forged[0].subject+=1;} else if field==3 {forged[0].reference+=1;}
                else if field==4 {forged[0].one+=1;} else {forged[0].addition+=1;}
                assert(!refinement_guard_verify::verify_evidence(source,p.program,forged));
            }
            assert(!refinement_guard_verify::verify_evidence(source,p.program,evidence.evidence[..evidence.evidence.len-1]));
        }
        var found=false;
        for n in p.program.nodes.len {
            if p.program.nodes[n].tag==18 {
                found=true;let old=p.program.nodes[n].tag;p.program.nodes[n].tag=9;
                assert(!unified_check::verify(source,p.program) && unified_wasm::emit(source,p.program).len==0);p.program.nodes[n].tag=old;break;
            }
        }
        if i<7 && i!=1 && i!=5 {assert(found);}
        let bytes=unified_wasm::emit(source,p.program);assert(bytes.len>0 && write_file(str("ule-",i,".wasm"),bytes));
    }
    for bad in [
      "let f: U32 -> U32 = fn x => do:\n  if x <= 4294967295:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if 4294967294 <= x:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if 4294967294 < x:\n    return x + 1\n  else:\n    return x\n",
      "let f: U32 -> U32 = fn x => do:\n  if x <= 4294967294:\n    return x\n  else:\n    return x + 1\n",
      "let f: U32 -> U32 = fn x => do:\n  if x <= 4294967294 || x + 1 <= 5:\n    return x\n  else:\n    return x\n"
    ] { let p=unified_frontend::parse(bad);assert(p.status==5 && p.program.nodes.len==0); }
    print("unified U32 <= and exact guarded evidence passed");
}
